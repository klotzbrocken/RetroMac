// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry


/**
 * Namespace for the main screensaver/GL logic
 */
Flurry.GLSaver = {};

/**
 * @private
 * @static
 * @type {number}
 */
Flurry.GLSaver.timeCounter = 0;

Flurry.GLSaver.State = {};
/** @type {Flurry.Spark[]} */
Flurry.GLSaver.State.spark     = ArrayOf(Flurry.Spark, 32);
/** @type {Flurry.Smoke} */
Flurry.GLSaver.State.smoke     = new Flurry.Smoke();
/** @type {Flurry.Star} */
Flurry.GLSaver.State.star      = new Flurry.Star();
/** @type {number} */
Flurry.GLSaver.State.time      = 0; // fTime
/** @type {number} */
Flurry.GLSaver.State.randSeed  = Math.randFlt(0, 300);
/** @type {number} */
Flurry.GLSaver.State.oldTime   = 0; // fOldTime
/** @type {number} */
Flurry.GLSaver.State.deltaTime = 0; // fDeltaTime
/** @type {number} */
Flurry.GLSaver.State.frame     = 0; // dframe
/** @type {number} */
Flurry.GLSaver.State.drag      = 0;

/**
 * @static
 * @function
 */
Flurry.GLSaver.timeSinceStart = function()
{
    return (Date.now() - Flurry.GLSaver.timeCounter) / 1000;
};

/**
 * @static
 * @function
 */
Flurry.GLSaver.setup = function()
{
    var glSaver = Flurry.GLSaver,
        state   = glSaver.State;

    if (Flurry.GLSaver.timeCounter == 0)
        Flurry.GLSaver.timeCounter = Date.now();

    console.log("[GLSaver] Creating Flurry texture...");
    Flurry.Texture.create();

    console.log("[GLSaver] Creating objects...");
    state.smoke.init();
    state.star.init();

    for (var i = 0; i < 32; i++)
        state.spark[i].init(i);

    for (i = 0; i < MAX_SMOKE / 4; i++)
        for (var k = 0; k < 4; k++)
            state.smoke.particles[i].dead[k] = 1;

    for (i = 0; i < 12; i++)
        state.spark[i].update();

    console.log("[GLSaver] Setting up scene...");
    state.oldTimer = glSaver.timeSinceStart() + state.randSeed;
};

/**
 * @static
 * @function
 */
Flurry.GLSaver.render = function()
{
    window.requestAnimationFrame(Flurry.GLSaver.render);

    var state  = Flurry.GLSaver.State,
        config = Flurry.Config;

    state.frame++;
    state.oldTime   = state.time;
    state.time      = Flurry.GLSaver.timeSinceStart() + state.randSeed;
    state.deltaTime = state.time - state.oldTime;
    state.drag      = Math.pow(0.9965, state.deltaTime * 85);

    state.star.update();

    for (var i = 0; i < config.numStreams; i++)
        state.spark[i].update();

    state.smoke.update();
    state.smoke.draw();

    Flurry.renderer.render();

    if (config.debugFps)
        Flurry.stats.update();
};