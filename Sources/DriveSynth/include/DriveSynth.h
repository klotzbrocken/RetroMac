// DriveSynth: real-time procedural mechanical drive sound engine.
// Pure C, allocation-free in the render path, safe to drive from any thread.

#ifndef DRIVESYNTH_H
#define DRIVESYNTH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DriveSynth DriveSynth;

// Drive profiles
#define DS_PROFILE_FLOPPY35   0
#define DS_PROFILE_FLOPPY525  1
#define DS_PROFILE_STEPPER    2
#define DS_PROFILE_IDE        3
#define DS_PROFILE_DESKTOP    4
#define DS_PROFILE_SERVER     5
#define DS_PROFILE_COUNT      6

// Activity sources
#define DS_MODE_LIVE     0   // follow real disk activity posted with ds_post_activity
#define DS_MODE_AMBIENT  1   // simulated light background activity
#define DS_MODE_BUSY     2   // simulated heavy workload

typedef struct {
    float   spin;       // rotation speed 0...1 (floppy: motor)
    float   headPos;    // 0 = outer edge, 1 = inner edge, < 0 = parked on ramp
    float   readLED;    // fraction of time the read LED was lit since last call
    float   writeLED;   // fraction of time the write LED was lit since last call
    int32_t power;      // requested power state as seen by the engine
    int32_t ready;      // spun up and serving requests
    int32_t silent;     // completely stopped; the audio engine can be shut down
    int32_t profile;    // active profile
} DSStatus;

DriveSynth *ds_create(double sampleRate, uint32_t seed);
void ds_destroy(DriveSynth *s);

// Render mono float samples. Call from the audio thread only.
void ds_render(DriveSynth *s, float *out, int32_t frames);

// Controls (any thread).
void ds_set_power(DriveSynth *s, int32_t on);
void ds_set_profile(DriveSynth *s, int32_t profile);
void ds_set_mode(DriveSynth *s, int32_t mode);
void ds_set_volume(DriveSynth *s, float volume);   // 0...1
void ds_set_hum(DriveSynth *s, float hum);         // 0...1 motor / spindle level
// Post real disk activity deltas (counts since last post). Single producer.
void ds_post_activity(DriveSynth *s, uint64_t readOps, uint64_t writeOps,
                      uint64_t readBytes, uint64_t writeBytes);

void ds_get_status(DriveSynth *s, DSStatus *status);

#ifdef __cplusplus
}
#endif

#endif
