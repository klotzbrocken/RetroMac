// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

Flurry.Smoke = function()
{
    /** @type {Flurry.SmokeParticle[]} */
    this.particles = ArrayOf(Flurry.SmokeParticle, MAX_SMOKE / 4); // p

    /** @type {number} */
    this.nextParticle     = 0;
    /** @type {number} */
    this.nextSubParticle  = 0;
    /** @type {number} */
    this.lastParticleTime = 0;

    /** @type {Float32Array} */
    this.oldPos    = new Float32Array(3);
    /** @type {boolean} */
    this.firstTime = false;
    /** @type {number} */
    this.frame     = 0;

    /**
     * Buffer for the smoke mesh vertex positions. Big enough for each particle, times
     * four verticies, times two components (XY)
     *
     * SIMD.js: Original Flurry source dictates seraphimVertices as an array of 4
     * -component vectors, whereas here we are flattening the entire thing into one
     * array.
     *
     * Thus, I do not think this could benefit from being vectorized, or from SIMD
     * operations, as the flattening is nessecary for WebGL AFAIK.
     * @type {Float32Array}
     */
    this.seraphimVertices = new Float32Array(MAX_SMOKE * 4 * 2);

    /**
     * An all-zero buffer of seraphimVertices's size, to allow for quick blanking
     * without having to create a new array each frame.
     * @type {Float32Array}
     */
    this.seraphimVerticesBlank = new Float32Array(MAX_SMOKE * 4 * 2);

    /**
     * Buffer for the smoke mesh vertex indicies. Each particle is made up of two
     * triangles, so six indices per particle.
     * @type {Uint16Array}
     */
    this.seraphimIndicies = new Uint16Array(MAX_SMOKE * 6);

    /**
     * Buffer for the smoke mesh vertex UV coords. For each particle, times four
     * verticies, times two components (UV)
     * @type {Float32Array}
     */
    this.seraphimTextures = new Float32Array(MAX_SMOKE * 4 * 2);

    /**
     * Buffer for the smoke mesh vertex colors. For each particle, times four verticies,
     * times four components (RGBA)
     * @type {Float32Array}
     */
    this.seraphimColors = new Float32Array(MAX_SMOKE * 4 * 4);

    this.init = function()
    {
        this.nextParticle     = 0;
        this.nextSubParticle  = 0;
        this.lastParticleTime = 0.25;

        this.firstTime = true;
        this.frame     = 0;

        for (var i = 0; i < 3; i++)
            this.oldPos[i] = Math.randFlt(-100, 100);

        Flurry.renderer.setBuffer('position', this.seraphimVertices);
        Flurry.renderer.setBuffer('index',    this.seraphimIndicies);
        Flurry.renderer.setBuffer('color',    this.seraphimColors);
        Flurry.renderer.setBuffer('uv',       this.seraphimTextures);
    };

    /**
     * Based on UpdateSmoke_ScalarFrsqrte
     */
    this.update = function()
    {
        var state    = Flurry.GLSaver.State,
            config   = Flurry.Config,
            starPosX = state.star.pos[0],
            starPosY = state.star.pos[1],
            starPosZ = state.star.pos[2];

        this.frame++;

        if (this.firstTime)
        {
            this.firstTime        = false;
            this.lastParticleTime = state.time;
        }
        else if (state.time - this.lastParticleTime >= 1 / 121)
        {
            var dx = this.oldPos[0] - starPosX,
                dy = this.oldPos[1] - starPosY,
                dz = this.oldPos[2] - starPosZ,
                deltaPos = new Float32Array([dx * 5, dy * 5, dz * 5]);

            for (var i = 0; i < config.numStreams; i++)
            {
                this.particles[this.nextParticle].deltaPos[0][this.nextSubParticle] = deltaPos[0];
                this.particles[this.nextParticle].deltaPos[1][this.nextSubParticle] = deltaPos[1];
                this.particles[this.nextParticle].deltaPos[2][this.nextSubParticle] = deltaPos[2];
                this.particles[this.nextParticle].pos[0][this.nextSubParticle]      = starPosX;
                this.particles[this.nextParticle].pos[1][this.nextSubParticle]      = starPosY;
                this.particles[this.nextParticle].pos[2][this.nextSubParticle]      = starPosZ;
                this.particles[this.nextParticle].oldPos[0][this.nextSubParticle]   = starPosX;
                this.particles[this.nextParticle].oldPos[1][this.nextSubParticle]   = starPosY;
                this.particles[this.nextParticle].oldPos[2][this.nextSubParticle]   = starPosZ;

                var streamSpeedCoherenceFactor = Math.max( 0, 1 + Math.randBell(0.25*config.incohesion) ),
                    dX  = this.particles[this.nextParticle].pos[0][this.nextSubParticle] - state.spark[i].pos[0],
                    dY  = this.particles[this.nextParticle].pos[1][this.nextSubParticle] - state.spark[i].pos[1],
                    dZ  = this.particles[this.nextParticle].pos[2][this.nextSubParticle] - state.spark[i].pos[2],
                    rsq = (dX*dX+dY*dY+dZ*dZ),
                    f   = config.streamSpeed * 10 * streamSpeedCoherenceFactor,
                    mag = Math.frsqrte(rsq) * f;

                this.particles[this.nextParticle].deltaPos[0][this.nextSubParticle] -= (dX * mag);
                this.particles[this.nextParticle].deltaPos[1][this.nextSubParticle] -= (dY * mag);
                this.particles[this.nextParticle].deltaPos[2][this.nextSubParticle] -= (dZ * mag);
                this.particles[this.nextParticle].color[0][this.nextSubParticle] = state.spark[i].color[0] * (1 + Math.randBell(config.colorIncoherence));
                this.particles[this.nextParticle].color[1][this.nextSubParticle] = state.spark[i].color[1] * (1 + Math.randBell(config.colorIncoherence));
                this.particles[this.nextParticle].color[2][this.nextSubParticle] = state.spark[i].color[2] * (1 + Math.randBell(config.colorIncoherence));
                this.particles[this.nextParticle].color[3][this.nextSubParticle] = 0.85 * (1.0 + Math.randBell(0.5 * config.colorIncoherence));
                this.particles[this.nextParticle].time[this.nextSubParticle]  = state.time;
                this.particles[this.nextParticle].dead[this.nextSubParticle]  = 0;
                this.particles[this.nextParticle].frame[this.nextSubParticle] = (Math.randClib()) & 63;
                this.nextSubParticle++;

                if (this.nextSubParticle == 4)
                {
                    this.nextSubParticle = 0;
                    this.nextParticle++;
                }

                if (this.nextParticle >= MAX_SMOKE / 4)
                {
                    this.nextParticle    = 0;
                    this.nextSubParticle = 0;
                }
            }

            this.lastParticleTime = state.time;
        }

        this.oldPos.set(state.star.pos);

        var frameRate         = state.frame / state.time,
            frameRateModifier = 42.5 / frameRate;

        for (i = 0; i < MAX_SMOKE / 4; i++)
        for (var k = 0; k < 4; k++)
        {
            if (this.particles[i].dead[k] == 1)
                continue;

            var deltaX = this.particles[i].deltaPos[0][k],
                deltaY = this.particles[i].deltaPos[1][k],
                deltaZ = this.particles[i].deltaPos[2][k];

            for (var j = 0; j < config.numStreams; j++)
            {
                dX  = this.particles[i].pos[0][k] - state.spark[j].pos[0];
                dY  = this.particles[i].pos[1][k] - state.spark[j].pos[1];
                dZ  = this.particles[i].pos[2][k] - state.spark[j].pos[2];
                rsq = (dX*dX+dY*dY+dZ*dZ);
                f   = ((config.gravity * 10000) / rsq) * frameRateModifier;

                if ( (((i*4)+k) % config.numStreams) == j )
                    f *= 1 + config.streamBias;

                mag = f / Math.sqrt(rsq);

                deltaX -= (dX * mag);
                deltaY -= (dY * mag);
                deltaZ -= (dZ * mag);
            }

            deltaX *= state.drag;
            deltaY *= state.drag;
            deltaZ *= state.drag;

            if( (deltaX*deltaX+deltaY*deltaY+deltaZ*deltaZ) >= 25000000 )
            {
                this.particles[i].dead[k] = 1;
                continue;
            }

            this.particles[i].deltaPos[0][k] = deltaX;
            this.particles[i].deltaPos[1][k] = deltaY;
            this.particles[i].deltaPos[2][k] = deltaZ;

            for (j = 0; j < 3; j++)
            {
                this.particles[i].oldPos[j][k] = this.particles[i].pos[j][k];
                this.particles[i].pos[j][k] += (this.particles[i].deltaPos[j][k]) * state.deltaTime;
            }
        }
    };

    this.draw = function()
    {
        var particle,
            svii = 0,
            svi  = 0,
            sii  = 0,
            sti  = 0,
            sci  = 0,
            si   = 0,
            state       = Flurry.GLSaver.State,
            config      = Flurry.Config,
            screenW     = Flurry.renderer.canvas.clientWidth,
            screenH     = Flurry.renderer.canvas.clientHeight,
            screenRatio = screenW / screenH,
            wslash2     = screenW * 0.5,
            hslash2     = screenH * 0.5,
            streamSize  = config.streamSize * 1000,
            width       = (streamSize + 2.5 * config.streamExpansion) * screenRatio;

        this.seraphimVertices.set(this.seraphimVerticesBlank);

        // Per particle (group of four quads)
        for (var i = 0; i < MAX_SMOKE / 4; i++)
        {
            particle = this.particles[i];
            // Per quad in a particle
            for (var k = 0; k < 4; k++)
            {
                if (this.particles[i].dead[k] == 1)
                    continue;

                var thisWidth = (streamSize + (state.time - this.particles[i].time[k]) * config.streamExpansion) * screenRatio;

                if (thisWidth >= width)
                {
                    this.particles[i].dead[k] = 1;
                    continue;
                }

                var z    = this.particles[i].pos[2][k],
                    sx   = this.particles[i].pos[0][k] * screenW / z + wslash2,
                    sy   = this.particles[i].pos[1][k] * screenW / z + hslash2,
                    oldz = this.particles[i].oldPos[2][k];

                // Do not draw if out of bounds
                if (sx > screenW + 50 || sx < -50 || sy > screenH + 50 || sy < -50 || z < 25 || oldz < 25.)
                    continue;

                var w    = Math.max(1, thisWidth / z),
                    oldx = this.particles[i].oldPos[0][k],
                    oldy = this.particles[i].oldPos[1][k],

                    oldscreenx = (oldx * screenW / oldz) + wslash2,
                    oldscreeny = (oldy * screenW / oldz) + hslash2,
                    dx = (sx - oldscreenx),
                    dy = (sy - oldscreeny),
                    d  = Math.fastDist2D(dx, dy),
                    sm = d ? w / d : 0.0,
                    ow = Math.max(1, thisWidth / oldz),
                    os = d ? ow / d : 0.0;

                var cmv  = Vector4F(),
                    m    = 1 + sm,
                    dxs  = dx * sm,
                    dys  = dy * sm,
                    dxos = dx * os,
                    dyos = dy * os,
                    dxm  = dx * m,
                    dym  = dy * m;

                this.particles[i].frame[k]++;

                if (this.particles[i].frame[k] >= 64)
                    this.particles[i].frame[k] = 0;

                var u0 = (this.particles[i].frame[k] && 7) * 0.125,
                    v0 = (this.particles[i].frame[k] >> 3) * 0.125,
                    u1 = u0 + 0.125,
                    v1 = v0 + 0.125,
                    cm = 0.375 * config.brightness;

                cmv[0] = this.particles[i].color[0][k] * cm;
                cmv[1] = this.particles[i].color[1][k] * cm;
                cmv[2] = this.particles[i].color[2][k] * cm;
                cmv[3] = this.particles[i].color[3][k] * cm;

                for (var ci = 0; ci < 4; ci++)
                {
                    this.seraphimColors[sci++] = cmv[0];
                    this.seraphimColors[sci++] = cmv[1];
                    this.seraphimColors[sci++] = cmv[2];
                    this.seraphimColors[sci++] = cmv[3];
                }

                this.seraphimTextures[sti++] = u0;
                this.seraphimTextures[sti++] = v0;
                this.seraphimTextures[sti++] = u1;
                this.seraphimTextures[sti++] = v0;
                this.seraphimTextures[sti++] = u0;
                this.seraphimTextures[sti++] = v1;
                this.seraphimTextures[sti++] = u1;
                this.seraphimTextures[sti++] = v1;

                // Each seraphimVertices vector held the XY of two points in a quad
                var offset = (k-2) * config.focus;
                this.seraphimVertices[svi++] = sx + dxm - dys + offset;
                this.seraphimVertices[svi++] = sy + dym + dxs + offset;
                this.seraphimVertices[svi++] = sx + dxm + dys + offset;
                this.seraphimVertices[svi++] = sy + dym - dxs + offset;
                this.seraphimVertices[svi++] = oldscreenx - dxm - dyos + offset;
                this.seraphimVertices[svi++] = oldscreeny - dym + dxos + offset;
                this.seraphimVertices[svi++] = oldscreenx - dxm + dyos + offset;
                this.seraphimVertices[svi++] = oldscreeny - dym - dxos + offset;

                this.seraphimIndicies[sii++] = svii;
                this.seraphimIndicies[sii++] = svii + 2;
                this.seraphimIndicies[sii++] = svii + 1;
                this.seraphimIndicies[sii++] = svii + 2;
                this.seraphimIndicies[sii++] = svii + 3;
                this.seraphimIndicies[sii++] = svii + 1;

                si++; svii += 4;
            }
        }
    };
};