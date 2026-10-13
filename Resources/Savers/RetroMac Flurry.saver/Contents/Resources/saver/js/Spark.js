// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

/**
 * Represents a single physical "stream" attached to a flurry's star. Handles the
 * coloring and destination of their particles.
 * @constructor
 */
Flurry.Spark = function()
{
    /**
     * Represents the 3D position that particles of this stream should flow towards
     * @type {Float32Array}
     */
    this.pos      = Vector3F();
    /** @type {Float32Array} */
    this.oldPos   = Vector3F();
    /** @type {Float32Array} */
    this.deltaPos = Vector3F();

    /**
     * Represents RGB color that the next burst of particles from this stream will use
     * @type {Float32Array}
     */
    this.color = Vector3F();

    /**
     * Unique value that helps determine this stream's offset rotation from other streams
     * @type {number}
     */
    this.mystery = 0;

    this.init = function(spark)
    {
        this.mystery = ( BIG_MYSTERY * (spark + 1) ) / 32;

        for (var i = 0; i < 3; i++)
            this.pos[i] = Math.randFlt(-100, 100);
    };

    /**
     * Called every frame; should be as optimized as possible
     */
    this.update = function()
    {
        var state  = Flurry.GLSaver.State,
            config = Flurry.Config,

            rotsPerSecond = 2 * Math.PI * config.fieldSpeed / MAX_ANGLES;

        // Optimized from original code, which contained a duplicate of updateColor here
        this.updateColor();

        var thisAngle = state.time * rotsPerSecond;

        // Iterating instead of using Float32Array.set() as this is faster
        for (var i = 0; i < 3; i++)
            this.oldPos[i] = this.pos[i];

        var thisPointInRadians = 2 * Math.PI * this.mystery / BIG_MYSTERY,
            cf = (
                Math.cos( 7 * (state.time * rotsPerSecond) )
                + Math.cos( 3 * (state.time * rotsPerSecond) )
                + Math.cos( 13 * (state.time * rotsPerSecond) )
            );
        cf /= 6.0;
        cf += 2.0;

        this.pos[0] = config.fieldRange * 10 * cf * Math.cos(11.0 * (thisPointInRadians + (3.0*thisAngle)));
        this.pos[1] = config.fieldRange * 10 * cf * Math.sin(12.0 * (thisPointInRadians + (4.0*thisAngle)));
        this.pos[2] = config.fieldRange * 10 * Math.cos((23.0 * (thisPointInRadians + (12.0*thisAngle))));

        var rotation = thisAngle * 0.501 + 5.01 * this.mystery / BIG_MYSTERY,
            cr    = Math.cos(rotation),
            sr    = Math.sin(rotation),
            tmpX1 = this.pos[0] * cr - this.pos[1] * sr,
            tmpY1 = this.pos[1] * cr + this.pos[0] * sr,
            tmpZ1 = this.pos[2],

            tmpX2 = tmpX1 * cr - tmpZ1 * sr,
            tmpY2 = tmpY1,
            tmpZ2 = tmpZ1 * cr + tmpX1 * sr,

            tmpX3 = tmpX2,
            tmpY3 = tmpY2 * cr - tmpZ2 * sr,
            tmpZ3 = tmpZ2 * cr + tmpY2 * sr + config.seraphDistance * 10;

        rotation = thisAngle * 2.501 + 85.01 * this.mystery / BIG_MYSTERY;
        cr = Math.cos(rotation);
        sr = Math.sin(rotation);

        var tmpX4 = tmpX3 * cr - tmpY3 * sr,
            tmpY4 = tmpY3 * cr + tmpX3 * sr,
            tmpZ4 = tmpZ3;

        this.pos[0] = tmpX4 + Math.randBell(5 * config.fieldCoherence);
        this.pos[1] = tmpY4 + Math.randBell(5 * config.fieldCoherence);
        this.pos[2] = tmpZ4 + Math.randBell(5 * config.fieldCoherence);

        for (i=0;i<3;i++)
            this.deltaPos[i] = (this.pos[i] - this.oldPos[i]) / state.deltaTime;
    };

    /**
     * Called every frame; should be as optimized as possible
     */
    this.updateColor = function()
    {
        var state  = Flurry.GLSaver.State,
            config = Flurry.Config,
            rotsPerSecond = 2 * Math.PI * config.fieldSpeed / MAX_ANGLES;

        var thisAngle = state.time * rotsPerSecond,
            cycleTime = 20;

        switch (config.colorMode)
        {
            case ColorModes.Rainbow:
                cycleTime = 1.5; break;
            case ColorModes.Tiedye:
                cycleTime = 4.5; break;
            case ColorModes.Cyclic:
                cycleTime = 20; break;
            case ColorModes.SlowCyclic:
            default:
                cycleTime = 120; break;
        }

        var colorRot        = 2 * Math.PI / cycleTime,
            redPhaseShift   = 0,
            greenPhaseShift = cycleTime / 3,
            bluePhaseShift  = cycleTime * 2 / 3,
            colorTime       = state.time,
            baseRed, baseGreen, baseBlue;

        if (config.colorMode == ColorModes.White)
        {
            baseRed   = 0.1875;
            baseGreen = 0.1875;
            baseBlue  = 0.1875;
        }
        else if (config.colorMode == ColorModes.Multi)
        {
            baseRed   = 0.0625;
            baseGreen = 0.0625;
            baseBlue  = 0.0625;
        }
        else if (config.colorMode == ColorModes.Dark)
        {
            baseRed   = 0.0;
            baseGreen = 0.0;
            baseBlue  = 0.0;
        }
        else
        {
            if (config.colorMode < ColorModes.SlowCyclic)
                colorTime = (config.colorMode / 6) * cycleTime;
            else
                colorTime = state.time + state.randSeed;

            baseRed   = 0.109375 * (Math.cos((colorTime+redPhaseShift)*colorRot)   + 1);
            baseGreen = 0.109375 * (Math.cos((colorTime+greenPhaseShift)*colorRot) + 1);
            baseBlue  = 0.109375 * (Math.cos((colorTime+bluePhaseShift)*colorRot)  + 1);
        }

        var thisPointInRadians = 2 * Math.PI * this.mystery / BIG_MYSTERY;

        this.color[0] = baseRed   + 0.0625 * (0.5 + Math.cos((15.0 * (thisPointInRadians + 3.0*thisAngle))) + Math.sin((7.0 * (thisPointInRadians + thisAngle))));
        this.color[1] = baseGreen + 0.0625 * (0.5 + Math.sin(((thisPointInRadians) + thisAngle)));
        this.color[2] = baseBlue  + 0.0625 * (0.5 + Math.cos((37.0 * (thisPointInRadians + thisAngle))));
    };
};
