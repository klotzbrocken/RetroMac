// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

/**
 * Creates an equivalent of a 3 value float vector either from scratch, an existing
 * vector or an initial value
 * @param {Uint16Array|Float32Array|number=} [value=0]
 * @returns {Float32Array}
 */
Vector3F = function(value)
{
    if (value instanceof Uint16Array || value instanceof Float32Array)
        return new Float32Array(value);
    else
        return value
            ? new Float32Array([value, value, value])
            : new Float32Array(3);
};

/**
 * Creates an equivalent of a 4 value unsigned int vector either from scratch, an
 * existing vector or an initial value
 * @param {Uint16Array|Float32Array|number=} [value=0]
 * @returns {Uint16Array}
 */
Vector4I = function(value)
{
    if (value instanceof Uint16Array || value instanceof Float32Array)
        return new Uint16Array(value);
    else
        return value
            ? new Uint16Array([value, value, value, value])
            : new Uint16Array(4);
};

/**
 * Creates an equivalent of a 4 value float vector either from scratch, an existing
 * vector or an initial value
 * @param {Uint16Array|Float32Array|number=} [value=0]
 * @returns {Float32Array}
 */
Vector4F = function(value)
{
    if (value instanceof Uint16Array || value instanceof Float32Array)
        return new Float32Array(value);
    else
        return value
            ? new Float32Array([value, value, value, value])
            : new Float32Array(4);
};