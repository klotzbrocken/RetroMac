// DriveSynth.c
// Physically inspired procedural synthesis of mechanical drives:
//   spindle motor + bearings + air, voice coil and stepper actuators,
//   modal resonators for the arm and the chassis, floppy motor and media swish.
// A small actuator state machine services read/write requests the way a real
// drive does (seek, settle, rotational latency, transfer), so the rhythm of the
// clicks follows the real workload.

#include "DriveSynth.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

#define PI_F      3.14159265358979f
#define TWO_PI_F  6.28318530717959f
#define QCAP      64
#define COMB_MAX  4096

enum { K_FLOPPY = 0, K_VCM = 1, K_STEPPER = 2 };
enum { OP_READ = 0, OP_WRITE = 1, OP_INTERNAL = 2 };
enum { F_SET_READY = 1, F_SPINDOWN = 2, F_NOOP = 4, F_RECAL = 8, F_PARK = 16, F_UNPARK = 32 };
enum { A_IDLE = 0, A_PREDELAY, A_SEEK, A_SETTLE, A_ROT, A_XFER };

typedef struct {
    int   kind;
    float rpm, spinupTime, spindownTime;
    float humGain, harm[6];
    float whineMult, whineGain, whine2Mult, whine2Gain;
    float airGain, airCutoff, bearing;
    float motorHz, motorGain, swishGain, swishHz, motorRamp, motorIdleOff, headLoadGain;
    int   tracks;
    float stepMs, stepGain, stepChassis, finalGain, bangGain;
    float seekMinMs, seekMaxMs, settleMs;
    float clickGain, clickChassis, zipGain, zipHz, zipQ;
    float armF[4], armT[4], armG[4];
    float chF[3], chT[3], chG[3];
    float transferMBps;
    float parkGain, kickGain;
    float idleSeekRate, recalInterval;
    float opScale, maxPending;
    float caseMix, lpHz, outGain;
} Profile;

static const Profile PROFILES[DS_PROFILE_COUNT] = {
    [DS_PROFILE_FLOPPY35] = {
        .kind = K_FLOPPY, .rpm = 300,
        .motorHz = 210, .motorGain = 0.010f, .swishGain = 0.034f, .swishHz = 1700,
        .motorRamp = 0.35f, .motorIdleOff = 2.2f, .headLoadGain = 0.0f,
        .tracks = 80, .stepMs = 3.0f, .stepGain = 0.42f, .stepChassis = 0.16f,
        .finalGain = 0.0f, .bangGain = 1.25f, .settleMs = 15,
        .armF = {1250, 2650, 4100, 6400}, .armT = {0.030f, 0.022f, 0.014f, 0.009f},
        .armG = {1.0f, 0.75f, 0.5f, 0.3f},
        .chF = {170, 420, 860}, .chT = {0.07f, 0.05f, 0.035f}, .chG = {1.0f, 0.7f, 0.5f},
        .opScale = 0.20f, .maxPending = 6,
        .caseMix = 0.30f, .lpHz = 10000, .outGain = 1.0f,
    },
    [DS_PROFILE_FLOPPY525] = {
        .kind = K_FLOPPY, .rpm = 300,
        .motorHz = 95, .motorGain = 0.026f, .swishGain = 0.050f, .swishHz = 1150,
        .motorRamp = 0.55f, .motorIdleOff = 2.6f, .headLoadGain = 0.9f,
        .tracks = 40, .stepMs = 6.0f, .stepGain = 0.55f, .stepChassis = 0.33f,
        .finalGain = 0.5f, .bangGain = 1.9f, .settleMs = 20,
        .armF = {720, 1550, 2900, 4700}, .armT = {0.045f, 0.030f, 0.020f, 0.012f},
        .armG = {1.0f, 0.8f, 0.55f, 0.3f},
        .chF = {115, 270, 620}, .chT = {0.10f, 0.07f, 0.05f}, .chG = {1.0f, 0.75f, 0.5f},
        .opScale = 0.20f, .maxPending = 6,
        .caseMix = 0.38f, .lpHz = 8500, .outGain = 1.0f,
    },
    [DS_PROFILE_STEPPER] = {
        .kind = K_STEPPER, .rpm = 3600, .spinupTime = 8.0f, .spindownTime = 11.0f,
        .humGain = 0.040f, .harm = {1.0f, 0.7f, 0.55f, 0.4f, 0.25f, 0.2f},
        .whineMult = 68, .whineGain = 0.010f, .whine2Mult = 18, .whine2Gain = 0.007f,
        .airGain = 0.022f, .airCutoff = 2400, .bearing = 0.55f,
        .tracks = 200, .stepMs = 1.6f, .stepGain = 0.075f, .stepChassis = 0.04f,
        .finalGain = 8.0f, .bangGain = 1.0f, .settleMs = 18,
        .armF = {620, 1350, 2500, 4300}, .armT = {0.050f, 0.035f, 0.022f, 0.014f},
        .armG = {1.0f, 0.85f, 0.55f, 0.3f},
        .chF = {92, 210, 470}, .chT = {0.14f, 0.09f, 0.06f}, .chG = {1.0f, 0.7f, 0.45f},
        .transferMBps = 0.5f, .parkGain = 0.9f, .kickGain = 0.45f,
        .opScale = 0.7f, .maxPending = 20,
        .caseMix = 0.40f, .lpHz = 8000, .outGain = 1.0f,
    },
    [DS_PROFILE_IDE] = {
        .kind = K_VCM, .rpm = 5400, .spinupTime = 6.5f, .spindownTime = 9.0f,
        .humGain = 0.032f, .harm = {1.0f, 0.55f, 0.45f, 0.28f, 0.16f, 0.1f},
        .whineMult = 46, .whineGain = 0.011f, .whine2Mult = 11, .whine2Gain = 0.006f,
        .airGain = 0.024f, .airCutoff = 2300, .bearing = 0.6f,
        .seekMinMs = 3.0f, .seekMaxMs = 26.0f, .settleMs = 2.5f,
        .clickGain = 0.85f, .clickChassis = 0.35f, .zipGain = 0.22f, .zipHz = 1700, .zipQ = 2.2f,
        .armF = {960, 2150, 3650, 5800}, .armT = {0.032f, 0.022f, 0.015f, 0.010f},
        .armG = {1.0f, 0.8f, 0.55f, 0.32f},
        .chF = {140, 330, 720}, .chT = {0.08f, 0.055f, 0.04f}, .chG = {1.0f, 0.7f, 0.5f},
        .transferMBps = 8, .parkGain = 1.1f, .kickGain = 0.25f,
        .idleSeekRate = 0.06f, .recalInterval = 75,
        .opScale = 1.0f, .maxPending = 40,
        .caseMix = 0.32f, .lpHz = 9500, .outGain = 1.0f,
    },
    [DS_PROFILE_DESKTOP] = {
        .kind = K_VCM, .rpm = 7200, .spinupTime = 4.5f, .spindownTime = 8.0f,
        .humGain = 0.020f, .harm = {1.0f, 0.35f, 0.5f, 0.22f, 0.14f, 0.08f},
        .whineMult = 8, .whineGain = 0.004f, .whine2Mult = 31, .whine2Gain = 0.0035f,
        .airGain = 0.016f, .airCutoff = 3200, .bearing = 0.15f,
        .seekMinMs = 0.9f, .seekMaxMs = 17.0f, .settleMs = 1.3f,
        .clickGain = 0.70f, .clickChassis = 0.16f, .zipGain = 0.14f, .zipHz = 2600, .zipQ = 3.0f,
        .armF = {1450, 3150, 5000, 7600}, .armT = {0.022f, 0.015f, 0.010f, 0.007f},
        .armG = {1.0f, 0.85f, 0.6f, 0.35f},
        .chF = {180, 430, 950}, .chT = {0.05f, 0.035f, 0.025f}, .chG = {1.0f, 0.7f, 0.5f},
        .transferMBps = 80, .parkGain = 0.9f, .kickGain = 0.15f,
        .idleSeekRate = 0.03f,
        .opScale = 1.0f, .maxPending = 50,
        .caseMix = 0.24f, .lpHz = 12000, .outGain = 1.0f,
    },
    [DS_PROFILE_SERVER] = {
        .kind = K_VCM, .rpm = 15000, .spinupTime = 9.0f, .spindownTime = 14.0f,
        .humGain = 0.026f, .harm = {1.0f, 0.5f, 0.35f, 0.25f, 0.12f, 0.08f},
        .whineMult = 12, .whineGain = 0.012f, .whine2Mult = 4.5f, .whine2Gain = 0.007f,
        .airGain = 0.045f, .airCutoff = 4800, .bearing = 0.25f,
        .seekMinMs = 0.3f, .seekMaxMs = 7.5f, .settleMs = 0.6f,
        .clickGain = 0.55f, .clickChassis = 0.08f, .zipGain = 0.12f, .zipHz = 3500, .zipQ = 3.2f,
        .armF = {1950, 4000, 6300, 9300}, .armT = {0.016f, 0.011f, 0.008f, 0.005f},
        .armG = {1.0f, 0.85f, 0.6f, 0.35f},
        .chF = {230, 540, 1150}, .chT = {0.04f, 0.03f, 0.02f}, .chG = {1.0f, 0.6f, 0.4f},
        .transferMBps = 180, .parkGain = 0.8f, .kickGain = 0.2f,
        .idleSeekRate = 0.04f,
        .opScale = 1.3f, .maxPending = 80,
        .caseMix = 0.16f, .lpHz = 14000, .outGain = 0.95f,
    },
};

typedef struct { float a1, a2, b0, y1, y2, f, t, g; } Res;

typedef struct {
    int   type, flags;
    float target;   // VCM: 0..1 (negative = ramp); steppers: track number
    float pre;      // seconds to wait before seeking
    float rot;      // rotational latency, seconds
    float xfer;     // transfer time, seconds
    float gain;     // loudness multiplier
} Op;

struct DriveSynth {
    float sr, invSr;
    uint32_t rng;
    const Profile *p;
    int profileIdx;

    // control (written by UI thread)
    _Atomic int   reqPower, reqProfile, reqMode;
    _Atomic float reqVolume, reqHum;
    _Atomic uint64_t inROps, inWOps, inRBytes, inWBytes;
    uint64_t seenROps, seenWOps, seenRBytes, seenWBytes;

    // status (written by audio thread)
    _Atomic float stSpin, stHead;
    _Atomic uint32_t stReadOn, stWriteOn, stSamples;
    _Atomic int stReady, stSilent, stProfile, stPower;

    // engine state
    int power, mode, ready, silent, swapping, swapTo;
    float volSm, humSm, fade, fadeTarget;
    float silentTime;

    // spindle
    float spin, spinTarget, rotPh, whPh, wh2Ph, lfoPh1, lfoPh2;
    int   unparkDone;
    int   kicks; float kickTimer;
    float airLP, airHP, rough, airA, airHPa, roughA, roughNorm;

    // floppy motor
    float motor, motorTarget, idleTimer, mPh;
    float swIc1, swIc2, swA1, swA2, swA3;

    // resonators and excitation
    Res   arm[4], ch[3];
    float armNorm, chNorm;
    float armImp, chImp, burst, burstDecay, lastEx;

    // voice coil "zip"
    float zipIc1, zipIc2, zipA1, zipA2, zipA3, zipAmp;
    int   zipLeft, zipTotal;

    // actuator
    int   act, timer, ledType;
    Op    cur;
    float pos, seekFrom, seekTo, seekDist;
    int   seekLen, seekT;
    int   track, stepsLeft, stepDir, stepTimer, stepSamples, clunkTimer;
    Op    q[QCAP];
    int   qHead, qTail;

    // workload model
    float pendR, pendW, wcache, wcacheTimer, wflushAt, fdemand;
    int   writeToggle;
    float seqProb, bpoEMA, rateEMA, baseline, rEMA, wEMA;
    float simTimer, simPhaseT, simRateR, simRateW, simSeq;
    float recalTimer;

    // output
    float dcX, dcY, lp1, lp2, lpA;
    float comb1[COMB_MAX], comb2[COMB_MAX];
    int   c1len, c2len, c1i, c2i;
    float c1lp, c2lp;
};

// ---------------------------------------------------------------- utilities

static inline uint32_t xs32(uint32_t *st) {
    uint32_t x = *st; x ^= x << 13; x ^= x >> 17; x ^= x << 5; *st = x; return x;
}
static inline float rnd(DriveSynth *s) { return (float)(xs32(&s->rng) >> 8) * (1.0f / 16777216.0f); }
static inline float nz(DriveSynth *s) { return rnd(s) * 2.0f - 1.0f; }
static inline float rr(DriveSynth *s, float a, float b) { return a + (b - a) * rnd(s); }
static inline float clampf(float x, float a, float b) { return x < a ? a : (x > b ? b : x); }
static inline float wrap1(float x) { return x >= 1.0f ? x - floorf(x) : x; }
static inline int   msToSamples(DriveSynth *s, float ms) { return (int)(ms * 0.001f * s->sr + 0.5f); }

static void res_set(DriveSynth *s, Res *r, float f, float t60, float g) {
    if (f > s->sr * 0.45f) f = s->sr * 0.45f;
    float w = TWO_PI_F * f / s->sr;
    float rad = expf(-6.9078f / (t60 * s->sr));
    r->a1 = 2.0f * rad * cosf(w);
    r->a2 = rad * rad;
    r->b0 = g * sinf(w);
}

static inline float res_tick(Res *r, float x) {
    float y = r->b0 * x + r->a1 * r->y1 - r->a2 * r->y2;
    r->y2 = r->y1; r->y1 = y;
    return y;
}

static void svf_coeffs(float fc, float q, float sr, float *a1, float *a2, float *a3) {
    float g = tanf(PI_F * clampf(fc, 20.0f, sr * 0.45f) / sr);
    float k = 1.0f / q;
    *a1 = 1.0f / (1.0f + g * (g + k));
    *a2 = g * *a1;
    *a3 = g * *a2;
}

static inline float svf_bp(float x, float *ic1, float *ic2, float a1, float a2, float a3) {
    float v3 = x - *ic2;
    float v1 = a1 * *ic1 + a2 * v3;
    float v2 = *ic2 + a2 * *ic1 + a3 * v3;
    *ic1 = 2.0f * v1 - *ic1;
    *ic2 = 2.0f * v2 - *ic2;
    return v1;
}

// Retune the arm resonances: they shift slightly with arm position.
static void retune_arm(DriveSynth *s, float jitter) {
    const Profile *p = s->p;
    float posShift = 1.0f + 0.05f * (clampf(s->pos, 0.0f, 1.0f) - 0.5f);
    for (int k = 0; k < 4; k++) {
        float f = p->armF[k] * posShift * (1.0f + jitter * nz(s));
        res_set(s, &s->arm[k], f, p->armT[k], p->armG[k] * s->armNorm);
    }
}

static inline void hit(DriveSynth *s, float armAmp, float chAmp) {
    s->armImp += armAmp;
    s->chImp  += chAmp;
    if (armAmp > s->burst) s->burst = armAmp;
}

// ---------------------------------------------------------------- op queue

static inline int q_empty(DriveSynth *s) { return s->qHead == s->qTail; }
static void q_clear(DriveSynth *s) { s->qHead = s->qTail = 0; }
static void q_push(DriveSynth *s, int type, int flags, float target, float pre, float rot, float xfer, float gain) {
    int next = (s->qTail + 1) % QCAP;
    if (next == s->qHead) return; // full
    Op *o = &s->q[s->qTail];
    o->type = type; o->flags = flags; o->target = target;
    o->pre = pre; o->rot = rot; o->xfer = xfer; o->gain = gain;
    s->qTail = next;
}
static Op q_pop(DriveSynth *s) { Op o = s->q[s->qHead]; s->qHead = (s->qHead + 1) % QCAP; return o; }

// ---------------------------------------------------------------- profile + power

static void apply_profile(DriveSynth *s, int idx) {
    if (idx < 0 || idx >= DS_PROFILE_COUNT) idx = DS_PROFILE_DESKTOP;
    s->profileIdx = idx;
    s->p = &PROFILES[idx];
    const Profile *p = s->p;

    float gs = 0; for (int k = 0; k < 4; k++) gs += p->armG[k];
    s->armNorm = 1.0f / gs;
    float cs = 0; for (int k = 0; k < 3; k++) cs += p->chG[k];
    s->chNorm = 1.0f / cs;
    memset(s->arm, 0, sizeof(s->arm));
    memset(s->ch, 0, sizeof(s->ch));
    for (int k = 0; k < 3; k++) res_set(s, &s->ch[k], p->chF[k], p->chT[k], p->chG[k] * s->chNorm);

    s->spin = 0; s->spinTarget = 0; s->motor = 0; s->motorTarget = 0;
    s->unparkDone = 0; s->ready = 0; s->kicks = 0;
    s->act = A_IDLE; s->ledType = 0; q_clear(s);
    s->pendR = s->pendW = s->wcache = s->fdemand = 0;
    s->zipLeft = 0; s->clunkTimer = 0;
    s->armImp = s->chImp = s->burst = 0;
    if (p->kind == K_VCM)      { s->pos = -0.08f; }
    else if (p->kind == K_STEPPER) { s->track = p->tracks - 1; s->pos = 1.0f; }
    else                       { s->track = p->tracks / 2; s->pos = (float)s->track / (float)(p->tracks - 1); }
    retune_arm(s, 0.0f);

    s->airA   = 1.0f - expf(-TWO_PI_F * p->airCutoff / s->sr);
    s->airHPa = 1.0f - expf(-TWO_PI_F * 150.0f / s->sr);
    s->roughA = 1.0f - expf(-TWO_PI_F * 28.0f / s->sr);
    s->roughNorm = 1.0f / sqrtf(s->roughA * 0.5f) * 0.6f;
    if (p->kind == K_FLOPPY) svf_coeffs(p->swishHz, 0.9f, s->sr, &s->swA1, &s->swA2, &s->swA3);
    s->lpA = 1.0f - expf(-TWO_PI_F * p->lpHz / s->sr);
    s->recalTimer = p->recalInterval > 0 ? p->recalInterval * rr(s, 0.5f, 1.0f) : 0;
    s->simTimer = 0.5f; s->simPhaseT = 0;
    s->stepSamples = msToSamples(s, p->stepMs > 0 ? p->stepMs : 3.0f);
}

static void power_on(DriveSynth *s) {
    const Profile *p = s->p;
    s->power = 1;
    s->silent = 0;
    if (p->kind == K_FLOPPY) {
        // POST style drive check: recalibrate to track 0, step out and back.
        q_clear(s);
        q_push(s, OP_INTERNAL, F_RECAL, 0, 0.05f, 0, 0, 1.0f);
        q_push(s, OP_INTERNAL, 0, 2, 0.06f, 0, 0, 1.0f);
        q_push(s, OP_INTERNAL, F_SET_READY, 0, 0.08f, 0, 0, 1.0f);
    } else {
        s->spinTarget = 1.0f;
        s->ready = 0;
        s->unparkDone = 0;
        s->kicks = s->spin < 0.1f ? 3 : 0; s->kickTimer = 0.0f;
    }
}

static void power_off(DriveSynth *s) {
    const Profile *p = s->p;
    s->power = 0;
    s->ready = 0;
    q_clear(s);
    s->pendR = s->pendW = s->wcache = s->fdemand = 0;
    if (s->act != A_IDLE && s->act != A_SEEK) s->act = A_IDLE;
    if (s->act == A_SEEK && p->kind != K_VCM) { s->act = A_IDLE; }
    if (p->kind == K_FLOPPY) {
        s->act = A_IDLE;
        s->motorTarget = 0;
    } else if (!s->unparkDone) {
        s->spinTarget = 0; // heads never left the ramp
    } else if (p->kind == K_VCM) {
        q_push(s, OP_INTERNAL, F_PARK | F_SPINDOWN, -0.08f, 0.02f, 0, 0, 1.0f);
    } else {
        q_push(s, OP_INTERNAL, F_PARK | F_SPINDOWN, (float)(p->tracks - 1), 0.02f, 0, 0, 1.0f);
    }
}

// ---------------------------------------------------------------- actuator

static void after_seek(DriveSynth *s) {
    s->act = A_SETTLE;
    s->timer = msToSamples(s, s->p->settleMs);
}

static void finish_op(DriveSynth *s) {
    int flags = s->cur.flags;
    s->act = A_IDLE;
    if (flags & F_SET_READY) s->ready = 1;
    if (flags & F_SPINDOWN) { s->spinTarget = 0; s->unparkDone = 0; }
}

static void begin_seek(DriveSynth *s) {
    const Profile *p = s->p;
    Op *o = &s->cur;
    if (o->flags & F_NOOP) { finish_op(s); return; }

    if (p->kind == K_VCM) {
        float target = clampf(o->target, -0.1f, 1.0f);
        float dist = fabsf(target - s->pos);
        if (dist < 1e-5f) { after_seek(s); return; }
        float sd = sqrtf(fminf(dist, 1.0f));
        float dur = (p->seekMinMs + (p->seekMaxMs - p->seekMinMs) * sd) * 0.001f;
        float amp = p->clickGain * (0.12f + 0.88f * powf(dist, 0.4f)) * rr(s, 0.85f, 1.15f) * o->gain;
        retune_arm(s, 0.012f);
        hit(s, amp, amp * p->clickChassis * (0.3f + dist));
        if (o->flags & F_UNPARK) hit(s, p->parkGain * 0.55f, p->parkGain * 0.35f);
        // voice coil current "zip" during the move
        s->zipAmp = p->zipGain * sd * o->gain;
        s->zipTotal = s->zipLeft = (int)(dur * 0.9f * s->sr) + 1;
        s->seekFrom = s->pos; s->seekTo = target; s->seekDist = dist;
        s->seekLen = (int)(dur * s->sr) + 1; s->seekT = 0;
        s->act = A_SEEK;
    } else {
        if (o->flags & F_RECAL) {
            s->stepsLeft = p->tracks + 6;
            s->stepDir = -1;
        } else {
            int tgt = (int)(o->target + 0.5f);
            if (tgt < 0) tgt = 0;
            if (tgt > p->tracks - 1) tgt = p->tracks - 1;
            int d = tgt - s->track;
            s->stepsLeft = d < 0 ? -d : d;
            s->stepDir = d < 0 ? -1 : 1;
        }
        if (s->stepsLeft == 0) { after_seek(s); return; }
        s->stepTimer = 1;
        s->act = A_SEEK;
    }
}

static void start_op(DriveSynth *s, Op o) {
    s->cur = o;
    s->ledType = (o.type == OP_WRITE) ? 2 : (o.type == OP_READ ? 1 : (s->p->kind == K_FLOPPY ? 1 : 0));
    if (o.pre > 0) { s->act = A_PREDELAY; s->timer = (int)(o.pre * s->sr) + 1; return; }
    begin_seek(s);
}

static void do_step(DriveSynth *s) {
    const Profile *p = s->p;
    float g = s->cur.gain;
    if (s->stepDir < 0 && s->track == 0) {
        // head hits the track 0 stop
        hit(s, p->stepGain * p->bangGain * rr(s, 0.85f, 1.1f) * g, p->stepChassis * p->bangGain * 1.6f * g);
    } else {
        s->track += s->stepDir;
        hit(s, p->stepGain * rr(s, 0.88f, 1.08f) * g, p->stepChassis * rr(s, 0.8f, 1.1f) * g);
    }
    s->pos = (float)s->track / (float)(p->tracks - 1);
    s->stepsLeft--;
    if (s->stepsLeft > 0) {
        s->stepTimer = (int)(s->stepSamples * rr(s, 0.985f, 1.015f));
    } else {
        if (p->finalGain > 0) s->clunkTimer = s->stepSamples + s->stepSamples / 2;
        if ((s->track & 7) == 0) retune_arm(s, 0.01f);
        after_seek(s);
    }
}

static inline void act_tick(DriveSynth *s) {
    const Profile *p = s->p;
    switch (s->act) {
    case A_IDLE:
        break;
    case A_PREDELAY:
        if (--s->timer <= 0) begin_seek(s);
        break;
    case A_SEEK:
        if (p->kind == K_VCM) {
            s->seekT++;
            float t = (float)s->seekT / (float)s->seekLen;
            if (t >= 1.0f) {
                s->pos = s->seekTo;
                float amp = p->clickGain * 0.5f * (0.15f + 0.85f * powf(s->seekDist, 0.4f)) * rr(s, 0.8f, 1.2f) * s->cur.gain;
                hit(s, amp, amp * p->clickChassis * 0.5f);
                if (s->cur.flags & F_PARK) hit(s, p->parkGain * 0.8f, p->parkGain * 0.9f);
                after_seek(s);
            } else {
                float sm = t * t * (3.0f - 2.0f * t);
                s->pos = s->seekFrom + (s->seekTo - s->seekFrom) * sm;
            }
        } else {
            if (--s->stepTimer <= 0) do_step(s);
        }
        break;
    case A_SETTLE:
        if (--s->timer <= 0) {
            if (s->cur.xfer <= 0 && s->cur.rot <= 0) { finish_op(s); break; }
            s->act = A_ROT;
            s->timer = (int)(s->cur.rot * s->sr) + 1;
        }
        break;
    case A_ROT:
        if (p->kind == K_FLOPPY && s->motor < 0.85f) break; // wait for the disk to spin up
        if (--s->timer <= 0) {
            s->act = A_XFER;
            s->timer = (int)(s->cur.xfer * s->sr) + 1;
        }
        break;
    case A_XFER:
        if (--s->timer <= 0) finish_op(s);
        break;
    }
}

// ---------------------------------------------------------------- workload

static void push_hdd_op(DriveSynth *s, int type) {
    const Profile *p = s->p;
    float rotP = 60.0f / p->rpm;
    float target, rot;
    int seq = rnd(s) < s->seqProb;
    if (p->kind == K_VCM) {
        if (seq) {
            target = s->pos + 0.0006f * rr(s, 0.5f, 2.0f);
            if (target > 1.0f) target = rnd(s);
            rot = rnd(s) * 0.12f * rotP;
        } else if (type == OP_WRITE && (s->writeToggle ^= 1)) {
            target = 0.06f + rnd(s) * 0.03f; // journal / metadata area
            rot = rnd(s) * rotP;
        } else if (rnd(s) < 0.5f) {
            target = clampf(s->pos + (rnd(s) - 0.5f) * 0.08f, 0.0f, 1.0f);
            rot = rnd(s) * rotP;
        } else {
            target = rnd(s);
            rot = rnd(s) * rotP;
        }
    } else { // stepper HDD
        float tr = (float)s->track;
        if (seq) { target = tr + 1; if (target > p->tracks - 1) target = 4; rot = rnd(s) * 0.1f * rotP; }
        else if (type == OP_WRITE && (s->writeToggle ^= 1)) { target = (float)(int)rr(s, 0, 3); rot = rnd(s) * rotP; }
        else if (rnd(s) < 0.45f) { target = clampf(tr + (float)(int)rr(s, -18, 18), 0, (float)(p->tracks - 1)); rot = rnd(s) * rotP; }
        else { target = (float)(int)rr(s, 0, (float)p->tracks); rot = rnd(s) * rotP; }
    }
    float bpo = clampf(s->bpoEMA, 4096.0f, 4.0e6f);
    float xfer = clampf(bpo / (p->transferMBps * 1.0e6f), 0.0002f, 0.03f);
    q_push(s, type, 0, target, 0, rot, xfer, 1.0f);
}

// A DOS style file access on a floppy: FAT, directory, then sequential tracks.
static void push_floppy_file(DriveSynth *s, int write, int n) {
    const Profile *p = s->p;
    float rotP = 60.0f / p->rpm;
    if (n < 1) n = 1;
    if (n > 8) n = 8;
    q_push(s, OP_READ, 0, 0, 0, rnd(s) * rotP, rotP, 1.0f);
    if (rnd(s) < 0.6f) q_push(s, OP_READ, 0, 1, 0, rnd(s) * rotP, rotP, 1.0f);
    int start = (int)rr(s, 2.0f, (float)(p->tracks - n - 1));
    for (int i = 0; i < n; i++) {
        float rot = (i == 0) ? rnd(s) * rotP : rnd(s) * 0.15f * rotP;
        q_push(s, write ? OP_WRITE : OP_READ, 0, (float)(start + i), 0, rot, 2.0f * rotP, 1.0f);
    }
    if (write) {
        q_push(s, OP_WRITE, 0, 0, 0, rnd(s) * rotP, rotP, 1.0f);
        q_push(s, OP_WRITE, 0, 1, 0, rnd(s) * rotP, rotP, 1.0f);
    }
}

static void simulate(DriveSynth *s, float dt) {
    const Profile *p = s->p;
    int idle = (s->act == A_IDLE && q_empty(s));
    if (p->kind == K_FLOPPY) {
        s->simTimer -= dt;
        if (s->simTimer <= 0 && idle) {
            if (s->mode == DS_MODE_BUSY) {
                push_floppy_file(s, rnd(s) < 0.4f, (int)rr(s, 2, 9));
                s->simTimer = rr(s, 0.2f, 1.5f);
            } else {
                push_floppy_file(s, rnd(s) < 0.25f, (int)rr(s, 1, 5));
                s->simTimer = rr(s, 4.0f, 14.0f);
            }
        }
        return;
    }
    if (s->mode == DS_MODE_AMBIENT) {
        s->simTimer -= dt;
        if (s->simTimer <= 0) {
            float r = rnd(s);
            if (r < 0.55f)      s->pendR += rr(s, 1, 4);
            else if (r < 0.80f) s->wcache += rr(s, 2, 7);
            else if (r < 0.92f) { s->simPhaseT = rr(s, 1.0f, 3.5f); s->simRateR = 25; s->simRateW = 0; s->simSeq = 0.9f; }
            else                s->pendR += rr(s, 6, 16);
            s->simTimer = rr(s, 1.5f, 8.5f);
        }
        if (s->simPhaseT > 0) {
            s->simPhaseT -= dt;
            s->pendR += s->simRateR * dt;
            s->seqProb = s->simSeq;
        } else {
            s->seqProb = 0.15f;
        }
    } else { // busy
        s->simPhaseT -= dt;
        if (s->simPhaseT <= 0) {
            int ph = (int)rr(s, 0, 5);
            switch (ph) {
            case 0: s->simRateR = rr(s, 30, 80); s->simRateW = 0;  s->simSeq = 0.1f;  s->simPhaseT = rr(s, 1, 4); break;
            case 1: s->simRateR = 60;            s->simRateW = 0;  s->simSeq = 0.95f; s->simPhaseT = rr(s, 2, 5); break;
            case 2: s->simRateR = 5;  s->simRateW = rr(s, 30, 60); s->simSeq = 0.3f;  s->simPhaseT = rr(s, 1, 2.5f); break;
            case 3: s->simRateR = 20; s->simRateW = 20;            s->simSeq = 0.3f;  s->simPhaseT = rr(s, 2, 4); break;
            default: s->simRateR = 0; s->simRateW = 0;             s->simSeq = 0.2f;  s->simPhaseT = rr(s, 0.2f, 1.2f); break;
            }
        }
        s->pendR += s->simRateR * dt;
        s->wcache += s->simRateW * dt;
        s->seqProb = s->simSeq;
    }
}

static void ingest(DriveSynth *s, float dt) {
    const Profile *p = s->p;
    uint64_t ro = atomic_load_explicit(&s->inROps, memory_order_relaxed);
    uint64_t wo = atomic_load_explicit(&s->inWOps, memory_order_relaxed);
    uint64_t rb = atomic_load_explicit(&s->inRBytes, memory_order_relaxed);
    uint64_t wb = atomic_load_explicit(&s->inWBytes, memory_order_relaxed);
    float dR  = (float)(ro - s->seenROps), dW = (float)(wo - s->seenWOps);
    float dRB = (float)(rb - s->seenRBytes), dWB = (float)(wb - s->seenWBytes);
    s->seenROps = ro; s->seenWOps = wo; s->seenRBytes = rb; s->seenWBytes = wb;

    if (!s->power) return;

    if (s->mode != DS_MODE_LIVE) {
        simulate(s, dt);
    } else {
        float dOps = dR + dW;
        float inst = dOps / dt;
        s->rateEMA += (inst - s->rateEMA) * fminf(1.0f, dt / 0.8f);
        float tau = s->rateEMA > s->baseline ? 25.0f : 4.0f;
        s->baseline += (s->rateEMA - s->baseline) * fminf(1.0f, dt / tau);
        float base = fminf(s->baseline, 60.0f);
        float eff = fmaxf(0.0f, s->rateEMA - 0.75f * base);
        float target = 0.6f * powf(eff, 0.8f) * p->opScale;
        float f = s->rateEMA > 0.5f ? clampf(target / s->rateEMA, 0.0f, 1.0f) : 0.0f;
        if (dOps > 0) {
            float bpo = (dRB + dWB) / dOps;
            s->bpoEMA += (bpo - s->bpoEMA) * 0.25f;
            s->seqProb = clampf((log2f(fmaxf(s->bpoEMA, 1.0f)) - 14.5f) / 4.5f, 0.05f, 0.9f);
            s->rEMA += (dR - s->rEMA) * 0.2f;
            s->wEMA += (dW - s->wEMA) * 0.2f;
        }
        if (p->kind == K_FLOPPY) {
            s->fdemand += dOps * f;
        } else {
            s->pendR += dR * f;
            s->wcache += dW * f;
        }
    }

    if (p->kind == K_FLOPPY) {
        if (s->mode == DS_MODE_LIVE && s->ready && s->act == A_IDLE && q_empty(s) && s->fdemand >= 1.0f) {
            int n = (int)clampf(s->fdemand, 1, 6);
            push_floppy_file(s, s->wEMA > s->rEMA * 1.2f, n);
            s->fdemand = 0;
        }
        s->fdemand = fminf(s->fdemand, 8.0f);
        return;
    }

    // write-back cache: writes leave in bursts
    if (s->wcache > 0.0f) {
        if (s->wcacheTimer == 0.0f) s->wflushAt = rr(s, 0.25f, 1.1f);
        s->wcacheTimer += dt;
        if (s->wcacheTimer >= s->wflushAt || s->wcache > 24.0f) {
            s->pendW += s->wcache;
            s->wcache = 0; s->wcacheTimer = 0;
        }
    }
    s->pendR = fminf(s->pendR, p->maxPending);
    s->pendW = fminf(s->pendW, p->maxPending);

    if (s->ready) {
        if (p->idleSeekRate > 0 && rnd(s) < p->idleSeekRate * dt)
            q_push(s, OP_INTERNAL, 0, p->kind == K_VCM ? rnd(s) : (float)(int)rr(s, 0, (float)p->tracks), 0, 0, 0, 0.7f);
        if (p->recalInterval > 0) {
            s->recalTimer -= dt;
            if (s->recalTimer <= 0) {
                float back = s->pos;
                q_push(s, OP_INTERNAL, 0, 0.0f, 0.02f, 0, 0, 0.9f);
                q_push(s, OP_INTERNAL, 0, 1.0f, 0.03f, 0, 0, 0.9f);
                q_push(s, OP_INTERNAL, 0, back, 0.03f, 0, 0, 0.9f);
                s->recalTimer = p->recalInterval * rr(s, 0.7f, 1.3f);
            }
        }
    }
}

static void schedule(DriveSynth *s) {
    const Profile *p = s->p;
    if (s->act != A_IDLE) return;
    if (!q_empty(s)) { start_op(s, q_pop(s)); return; }
    if (!s->ready || p->kind == K_FLOPPY) return;
    int canR = s->pendR >= 1.0f, canW = s->pendW >= 1.0f;
    if (canW && (!canR || rnd(s) < 0.5f)) { s->pendW -= 1.0f; push_hdd_op(s, OP_WRITE); start_op(s, q_pop(s)); }
    else if (canR) { s->pendR -= 1.0f; push_hdd_op(s, OP_READ); start_op(s, q_pop(s)); }
}

// ---------------------------------------------------------------- spindle / motor control (per block)

static void spindle_block(DriveSynth *s, float dt) {
    const Profile *p = s->p;
    if (p->kind == K_FLOPPY) {
        int busy = (s->act != A_IDLE) || !q_empty(s);
        if (busy) s->idleTimer = 0; else s->idleTimer += dt;
        float prevT = s->motorTarget;
        s->motorTarget = (busy || (s->power && s->idleTimer < p->motorIdleOff)) && (busy || s->motor > 0.0f) ? 1.0f : 0.0f;
        if (!s->power && !busy) s->motorTarget = 0.0f;
        if (p->headLoadGain > 0) {
            if (s->motorTarget > prevT) hit(s, p->headLoadGain * 0.45f, p->headLoadGain * 0.7f);
            else if (s->motorTarget < prevT) hit(s, p->headLoadGain * 0.25f, p->headLoadGain * 0.35f);
        }
        float rate = dt / p->motorRamp;
        if (s->motorTarget > s->motor) s->motor = fminf(s->motorTarget, s->motor + rate);
        else s->motor = fmaxf(0.0f, s->motor - rate * 0.8f);
        return;
    }
    if (s->spinTarget > 0.5f) {
        float a = 3.04f / p->spinupTime;
        s->spin += a * (1.05f - s->spin) * dt;
        if (s->spin > 1.0f) s->spin = 1.0f;
        if (s->kicks > 0) {
            s->kickTimer -= dt;
            if (s->kickTimer <= 0) {
                hit(s, p->kickGain * 0.2f, p->kickGain * rr(s, 0.8f, 1.1f));
                s->kicks--; s->kickTimer = rr(s, 0.06f, 0.11f);
            }
        }
        if (!s->unparkDone && s->spin > 0.97f && s->power) {
            s->unparkDone = 1;
            if (p->kind == K_VCM) {
                q_push(s, OP_INTERNAL, F_UNPARK, 0.02f, 0.05f, 0, 0, 1.0f);
                static const float cal[6][2] = {{1.0f, 0.18f}, {0.0f, 0.10f}, {0.5f, 0.22f}, {0.12f, 0.35f}, {0.88f, 0.08f}, {0.3f, 0.25f}};
                for (int i = 0; i < 6; i++) q_push(s, OP_INTERNAL, 0, cal[i][0], cal[i][1], 0, 0, 1.0f);
            } else {
                q_push(s, OP_INTERNAL, 0, 0, 0.05f, 0, 0, 1.0f);
                q_push(s, OP_INTERNAL, 0, 120, 0.25f, 0, 0, 1.0f);
                q_push(s, OP_INTERNAL, 0, 8, 0.18f, 0, 0, 1.0f);
                q_push(s, OP_INTERNAL, 0, 60, 0.30f, 0, 0, 1.0f);
            }
            q_push(s, OP_INTERNAL, F_SET_READY | F_NOOP, 0, 0.1f, 0, 0, 1.0f);
        }
    } else {
        float tau = p->spindownTime / 3.0f;
        s->spin -= (s->spin / tau + 0.01f) * dt;
        if (s->spin < 0.0f) s->spin = 0.0f;
    }
}

// ---------------------------------------------------------------- public API

DriveSynth *ds_create(double sampleRate, uint32_t seed) {
    DriveSynth *s = (DriveSynth *)calloc(1, sizeof(DriveSynth));
    if (!s) return NULL;
    s->sr = (float)(sampleRate > 8000 ? sampleRate : 48000);
    s->invSr = 1.0f / s->sr;
    s->rng = seed ? seed : 0x9E3779B9u;
    atomic_store(&s->reqPower, 0);
    atomic_store(&s->reqProfile, DS_PROFILE_DESKTOP);
    atomic_store(&s->reqMode, DS_MODE_LIVE);
    atomic_store(&s->reqVolume, 0.6f);
    atomic_store(&s->reqHum, 0.7f);
    s->fade = 1.0f; s->fadeTarget = 1.0f;
    s->silent = 1;
    s->baseline = 10.0f;
    s->bpoEMA = 32768.0f;
    s->seqProb = 0.15f;
    s->burstDecay = expf(-1.0f / (0.00035f * s->sr));
    s->c1len = (int)(0.0031f * s->sr); if (s->c1len >= COMB_MAX) s->c1len = COMB_MAX - 1;
    s->c2len = (int)(0.0047f * s->sr); if (s->c2len >= COMB_MAX) s->c2len = COMB_MAX - 1;
    if (s->c1len < 8) s->c1len = 8;
    if (s->c2len < 8) s->c2len = 8;
    apply_profile(s, DS_PROFILE_DESKTOP);
    atomic_store(&s->stSilent, 1);
    atomic_store(&s->stProfile, DS_PROFILE_DESKTOP);
    return s;
}

void ds_destroy(DriveSynth *s) { free(s); }

void ds_set_power(DriveSynth *s, int32_t on) { atomic_store(&s->reqPower, on ? 1 : 0); if (on) atomic_store(&s->stSilent, 0); }
void ds_set_profile(DriveSynth *s, int32_t profile) {
    if (profile < 0 || profile >= DS_PROFILE_COUNT) return;
    atomic_store(&s->reqProfile, profile);
}
void ds_set_mode(DriveSynth *s, int32_t mode) { atomic_store(&s->reqMode, mode); }
void ds_set_volume(DriveSynth *s, float v) { atomic_store(&s->reqVolume, clampf(v, 0.0f, 1.0f)); }
void ds_set_hum(DriveSynth *s, float v) { atomic_store(&s->reqHum, clampf(v, 0.0f, 1.0f)); }

void ds_post_activity(DriveSynth *s, uint64_t ro, uint64_t wo, uint64_t rb, uint64_t wb) {
    atomic_fetch_add_explicit(&s->inROps, ro, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->inWOps, wo, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->inRBytes, rb, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->inWBytes, wb, memory_order_relaxed);
}

void ds_get_status(DriveSynth *s, DSStatus *st) {
    uint32_t n  = atomic_exchange(&s->stSamples, 0);
    uint32_t ro = atomic_exchange(&s->stReadOn, 0);
    uint32_t wo = atomic_exchange(&s->stWriteOn, 0);
    st->spin = atomic_load(&s->stSpin);
    st->headPos = atomic_load(&s->stHead);
    st->readLED  = n ? (float)ro / (float)n : 0.0f;
    st->writeLED = n ? (float)wo / (float)n : 0.0f;
    st->power = atomic_load(&s->stPower);
    st->ready = atomic_load(&s->stReady);
    st->silent = atomic_load(&s->stSilent);
    st->profile = atomic_load(&s->stProfile);
}

static inline float vol_curve(float v) { return powf(v, 1.7f) * 1.6f; }

static inline float soft_clip(float x) {
    if (x > 3.0f) return 1.0f;
    if (x < -3.0f) return -1.0f;
    float x2 = x * x;
    return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

void ds_render(DriveSynth *s, float *out, int32_t frames) {
    if (frames <= 0) return;
    float dt = (float)frames * s->invSr;

    // ---- control intake
    int reqProf = atomic_load_explicit(&s->reqProfile, memory_order_relaxed);
    if (reqProf != s->profileIdx && !s->swapping) {
        if (s->silent && !s->power) apply_profile(s, reqProf);
        else { s->swapping = 1; s->fadeTarget = 0.0f; }
    }
    if (s->swapping) s->swapTo = reqProf;
    if (s->swapping && s->fade < 0.002f) {
        int wasOn = s->power;
        apply_profile(s, s->swapTo);
        s->swapping = 0; s->fadeTarget = 1.0f;
        s->power = 0;
        if (wasOn && atomic_load(&s->reqPower)) power_on(s);
    }
    int reqPow = atomic_load_explicit(&s->reqPower, memory_order_relaxed);
    if (!s->swapping && reqPow != s->power) { if (reqPow) power_on(s); else power_off(s); }
    s->mode = atomic_load_explicit(&s->reqMode, memory_order_relaxed);
    float volT = vol_curve(atomic_load_explicit(&s->reqVolume, memory_order_relaxed));
    float humT = atomic_load_explicit(&s->reqHum, memory_order_relaxed);
    humT = humT * humT * 1.4f;

    const Profile *p = s->p;
    ingest(s, dt);
    spindle_block(s, dt);

    // slow wobble for spindle pitch
    s->lfoPh1 = wrap1(s->lfoPh1 + 0.37f * dt);
    s->lfoPh2 = wrap1(s->lfoPh2 + 0.83f * dt);
    float wob = 0.5f * sinf(TWO_PI_F * s->lfoPh1) + 0.5f * sinf(TWO_PI_F * s->lfoPh2);

    const int floppy = (p->kind == K_FLOPPY);
    const float sp = floppy ? s->motor : s->spin;
    const float spLevel = sp * sqrtf(sp);
    const float rotHz = p->rpm / 60.0f * sp;
    const float whHz  = rotHz * p->whineMult * (1.0f + 0.003f * wob);
    const float wh2Hz = rotHz * p->whine2Mult * (1.0f + 0.002f * wob);
    const float airA  = s->airA * (0.35f + 0.65f * sp);
    const float master = 0.80f * p->outGain;
    const float fadeA = 1.0f - expf(-1.0f / (0.012f * s->sr));
    const float smA = 1.0f - expf(-1.0f / (0.03f * s->sr));

    uint32_t readOn = 0, writeOn = 0;
    float peak = 0.0f;

    for (int i = 0; i < frames; i++) {
        schedule(s);
        act_tick(s);
        if (s->clunkTimer > 0 && --s->clunkTimer == 0)
            hit(s, p->stepGain * p->finalGain * rr(s, 0.9f, 1.1f) * 0.5f, p->stepChassis * p->finalGain);

        if (s->act != A_IDLE) {
            if (s->ledType == 1) readOn++;
            else if (s->ledType == 2) writeOn++;
        }

        s->volSm += (volT - s->volSm) * smA;
        s->humSm += (humT - s->humSm) * smA;
        s->fade  += (s->fadeTarget - s->fade) * fadeA;

        float x = 0.0f;

        // ---- rotation sources
        if (sp > 0.0005f) {
            s->rotPh = wrap1(s->rotPh + rotHz * s->invSr);
            float th = TWO_PI_F * s->rotPh;
            float s1 = sinf(th), c1 = cosf(th);
            if (!floppy) {
                float skm1 = 0.0f, sk = s1, acc = p->harm[0] * s1;
                for (int k = 1; k < 6; k++) {
                    float sn = 2.0f * c1 * sk - skm1;
                    skm1 = sk; sk = sn;
                    acc += p->harm[k] * sn;
                }
                s->whPh  = wrap1(s->whPh + whHz * s->invSr);
                s->wh2Ph = wrap1(s->wh2Ph + wh2Hz * s->invSr);
                float wh = (sinf(TWO_PI_F * s->whPh) * p->whineGain + sinf(TWO_PI_F * s->wh2Ph) * p->whine2Gain) * 1.4f;
                float n = nz(s);
                s->airLP += (n - s->airLP) * airA;
                s->airHP += (s->airLP - s->airHP) * s->airHPa;
                float air = s->airLP - s->airHP;
                s->rough += (nz(s) - s->rough) * s->roughA;
                float rough = 1.0f + p->bearing * s->rough * s->roughNorm;
                air *= p->airGain * rough * (1.0f + 0.12f * s1);
                x += ((acc * p->humGain + wh * (0.8f + 0.2f * rough)) * spLevel + air * spLevel) * s->humSm;
            } else {
                s->mPh = wrap1(s->mPh + p->motorHz * sp * s->invSr);
                float mth = TWO_PI_F * s->mPh;
                float hum = sinf(mth) + 0.35f * sinf(3.0f * mth);
                float bp = svf_bp(nz(s), &s->swIc1, &s->swIc2, s->swA1, s->swA2, s->swA3);
                float s2 = 2.0f * s1 * c1, c2 = 1.0f - 2.0f * s1 * s1;
                float am = 0.55f + 0.45f * (0.6f * s1 + 0.4f * (s2 * 0.2675f + c2 * 0.9636f));
                x += (hum * p->motorGain + bp * am * p->swishGain) * sp * sp * s->humSm;
            }
        }

        // ---- impacts through arm and chassis resonances
        float ex = s->armImp + nz(s) * s->burst * 0.10f;
        s->armImp = 0.0f;
        s->burst *= s->burstDecay;
        float ec = s->chImp;
        s->chImp = 0.0f;
        float armOut = res_tick(&s->arm[0], ex) + res_tick(&s->arm[1], ex) + res_tick(&s->arm[2], ex) + res_tick(&s->arm[3], ex);
        float chOut  = res_tick(&s->ch[0], ec) + res_tick(&s->ch[1], ec) + res_tick(&s->ch[2], ec);
        float tick = (ex - s->lastEx) * 0.12f;
        s->lastEx = ex;
        x += armOut + chOut + tick;

        // ---- voice coil zip
        if (s->zipLeft > 0) {
            float prog = 1.0f - (float)s->zipLeft / (float)s->zipTotal;
            if ((s->zipLeft & 7) == 0 || s->zipLeft == s->zipTotal)
                svf_coeffs(p->zipHz * (0.75f + 0.5f * sinf(PI_F * prog)), p->zipQ, s->sr, &s->zipA1, &s->zipA2, &s->zipA3);
            float env = sinf(PI_F * prog);
            float z = svf_bp(nz(s), &s->zipIc1, &s->zipIc2, s->zipA1, s->zipA2, s->zipA3);
            x += z * env * s->zipAmp;
            s->zipLeft--;
        }

        // ---- enclosure
        float c1v = s->comb1[s->c1i];
        float c2v = s->comb2[s->c2i];
        s->c1lp += (c1v - s->c1lp) * 0.35f;
        s->c2lp += (c2v - s->c2lp) * 0.30f;
        s->comb1[s->c1i] = x + s->c1lp * 0.55f;
        s->comb2[s->c2i] = x + s->c2lp * 0.50f;
        if (++s->c1i >= s->c1len) s->c1i = 0;
        if (++s->c2i >= s->c2len) s->c2i = 0;
        float y = x + p->caseMix * 0.5f * (c1v + c2v);

        // ---- output conditioning
        float hp = y - s->dcX + 0.9985f * s->dcY;
        s->dcX = y; s->dcY = hp;
        s->lp1 += (hp - s->lp1) * s->lpA;
        s->lp2 += (s->lp1 - s->lp2) * s->lpA;
        float o = soft_clip(s->lp2 * master * s->volSm * s->fade);
        out[i] = o;
        float ao = fabsf(s->lp2);
        if (ao > peak) peak = ao;
    }

    // flush denormal-ish tails
    for (int k = 0; k < 4; k++) { if (fabsf(s->arm[k].y1) < 1e-12f) { s->arm[k].y1 = 0; s->arm[k].y2 = 0; } }
    for (int k = 0; k < 3; k++) { if (fabsf(s->ch[k].y1) < 1e-12f) { s->ch[k].y1 = 0; s->ch[k].y2 = 0; } }

    // ---- silence detection
    int quiet = !s->power && !s->swapping && s->act == A_IDLE && q_empty(s) && s->spin < 0.001f && s->motor < 0.001f && peak < 1e-4f;
    if (quiet) s->silentTime += dt; else s->silentTime = 0.0f;
    if (s->power) s->silent = 0;
    else if (s->silentTime > 0.3f) s->silent = 1;

    // ---- status
    atomic_store_explicit(&s->stSpin, sp, memory_order_relaxed);
    atomic_store_explicit(&s->stHead, s->pos, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->stReadOn, readOn, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->stWriteOn, writeOn, memory_order_relaxed);
    atomic_fetch_add_explicit(&s->stSamples, (uint32_t)frames, memory_order_relaxed);
    atomic_store_explicit(&s->stReady, s->ready, memory_order_relaxed);
    atomic_store_explicit(&s->stSilent, s->silent && !atomic_load(&s->reqPower), memory_order_relaxed);
    atomic_store_explicit(&s->stProfile, s->profileIdx, memory_order_relaxed);
    atomic_store_explicit(&s->stPower, s->power, memory_order_relaxed);
}
