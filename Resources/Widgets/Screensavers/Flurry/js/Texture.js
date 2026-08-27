// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

Flurry.Texture = {};

/**
 * The WebGL texture used by Flurry
 * @type {WebGLTexture}
 */
Flurry.Texture.ref = null;

/** @type {Uint8Array[]} */
Flurry.Texture.smallTex = ArrayOf.ByteMatrix2(32, 32);

/** @type {Uint8Array[][]} */
Flurry.Texture.bigTex = ArrayOf.ByteMatrix3(256, 256, 2);

Flurry.Texture.firstTime = true;

Flurry.Texture.smooth = function()
{
    var i, j, t,
        filter = ArrayOf.ByteMatrix2(32, 32);

    for (i=1;i<31;i++)
    for (j=1;j<31;j++)
    {
        t  = Flurry.Texture.smallTex[i][j]*4;
        t += Flurry.Texture.smallTex[i-1][j];
        t += Flurry.Texture.smallTex[i+1][j];
        t += Flurry.Texture.smallTex[i][j-1];
        t += Flurry.Texture.smallTex[i][j+1];
        t /= 8;
        filter[i][j] = t;
    }

    for (i=1;i<31;i++)
    for (j=1;j<31;j++)
    {
        Flurry.Texture.smallTex[i][j] = filter[i][j];
    }
};

Flurry.Texture.speckle = function()
{
    var i, j, speck;

    for (i=2;i<30;i++)
    for (j=2;j<30;j++)
    {
        speck = 1;
        while (speck <= 32 && Math.randClib() % 2)
        {
            Flurry.Texture.smallTex[i][j] = Math.min(255, Flurry.Texture.smallTex[i][j] + speck);
            speck += speck;
        }

        speck = 1;
        while (speck <= 32 && Math.randClib() % 2)
        {
            Flurry.Texture.smallTex[i][j] = Math.max(0, Flurry.Texture.smallTex[i][j] - speck);
            speck += speck;
        }
    }
};

Flurry.Texture.makeSmallTexture = function()
{
    var i, j, t, r;

    if (Flurry.Texture.firstTime)
    {
        Flurry.Texture.firstTime = false;
        for (i=0;i<32;i++)
        for (j=0;j<32;j++)
        {
            r = Math.sqrt((i-15.5)*(i-15.5)+(j-15.5)*(j-15.5));
            if (r > 15)
                Flurry.Texture.smallTex[i][j] = 0;
            else
                Flurry.Texture.smallTex[i][j] = 255.0 * Math.cos(r*Math.PI/31.0);
        }

    }
    else
    {
        for (i=0;i<32;i++)
        for (j=0;j<32;j++)
        {
            r = Math.sqrt((i-15.5)*(i-15.5)+(j-15.5)*(j-15.5));
            if (r > 15.0)
                t = 0;
            else
                t = 255 * Math.cos(r*Math.PI/31.0);

            Flurry.Texture.smallTex[i][j] = Math.min(255, (t + Flurry.Texture.smallTex[i][j] + Flurry.Texture.smallTex[i][j]) / 3);
        }
    }

    Flurry.Texture.speckle();
    Flurry.Texture.smooth();
    Flurry.Texture.smooth();
};

/**
 * @static
 * @function
 */
Flurry.Texture.copySmallToBig = function(k, l)
{
    for (var i=0;i<32;i++)
    for (var j=0;j<32;j++)
    {
        Flurry.Texture.bigTex[i+k][j+l][0] = Flurry.Texture.smallTex[i][j];
        Flurry.Texture.bigTex[i+k][j+l][1] = Flurry.Texture.smallTex[i][j];
    }
};

/**
 * @static
 * @function
 */
Flurry.Texture.averageLastAndFirst = function()
{
    for (var i=0;i<32;i++)
    for (var j=0;j<32;j++)
    {
        var t = (Flurry.Texture.smallTex[i][j] + Flurry.Texture.bigTex[i][j][0]) / 2;
        Flurry.Texture.smallTex[i][j] = Math.min(255,t);
    }
};

/**
 * Creates textures for Flurry to use, referencing it in {Flurry.Texture.ref}
 * @static
 * @function
 */
Flurry.Texture.create = function()
{
    var gl = Flurry.renderer.gl;

    for (var i = 0; i < 8; i++)
    for (var j = 0; j < 8; j++)
    {
        if (i == 7 && j == 7)
            Flurry.Texture.averageLastAndFirst();
        else
            Flurry.Texture.makeSmallTexture();

        Flurry.Texture.copySmallToBig(i * 32, j * 32);
    }

    // Flatten bigTex
    var bigTexFlat = new Uint8Array(256 * 256 * 2);
    for (i = 0; i < 256; i++)
    for (j = 0; j < 256; j++)
    {
        var offset = (i*256*2 + j*2);
        bigTexFlat[offset]   = Flurry.Texture.bigTex[i][j][0];
        bigTexFlat[offset+1] = Flurry.Texture.bigTex[i][j][1];
    }

    Flurry.Texture.ref = gl.createTexture();

    gl.bindTexture(gl.TEXTURE_2D, Flurry.Texture.ref);
    gl.texImage2D(
        gl.TEXTURE_2D, 0,
        gl.LUMINANCE_ALPHA, 256, 256, 0,
        gl.LUMINANCE_ALPHA,
        gl.UNSIGNED_BYTE, bigTexFlat);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_NEAREST);
    gl.generateMipmap(gl.TEXTURE_2D);

    // TODO: WebGL (TexEnvF shader?)
    // See http://graphics.snu.ac.kr/class/graphics2011/materials/ch14_glsl.pdf
};