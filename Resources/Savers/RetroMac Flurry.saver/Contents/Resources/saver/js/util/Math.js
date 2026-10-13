// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

/**
 * Computes the distance from 0, 0 to x, y with ~3.5% error
 * @param x
 * @param y
 * @returns {number}
 */
Math.fastDist2D = function(x, y)
{
    x = (x < 0) ? -x : x;
    y = (y < 0) ? -y : y;

    var mn = x < y ? x : y;
    return (x + y - (mn * 0.5) - (mn * 0.25) + (mn * 0.0625));
};

Math.randClib = function()
{
    return Math.floor( Math.random() * 32767 );
};

Math.randFlt = function(min, max)
{
    return (min + (max - min) * Math.random());
};

Math.randBell = function(scale)
{
    return (scale * (1.0 - ( Math.random() + Math.random() + Math.random() ) / 1.5));
};

Math.frsqrteBuffer = new ArrayBuffer(Float32Array.BYTES_PER_ELEMENT);
Math.frsqrteFV     = new Float32Array(Math.frsqrteBuffer);
Math.frsqrteIV     = new Uint32Array(Math.frsqrteBuffer);

/**
 * Calculate the inverse square root of a given float. Replaces the PPC frsqrte asm
 * instruction and uses a fast approximation.
 * @seealso http://gamedev.stackexchange.com/a/30740
 * @param value
 * @returns {number}
 */
Math.frsqrte = function(value)
{
    var x2 = value * 0.5;
    Math.frsqrteFV[0] = value;
    Math.frsqrteIV[0] = 0x5f3759df - ( Math.frsqrteIV[0] >> 1 );
    var y = Math.frsqrteFV[0];

    return y * ( 1.5 - ( x2 * y * y ) );
};

/**
 * Returns 0 or 1 depending on the sign of the given value
 * @param value
 * @returns {number} 0 positive, 1 negative
 */
Math.sign = function(value)
{
    return value >= 0 ? 0 : 1;
};