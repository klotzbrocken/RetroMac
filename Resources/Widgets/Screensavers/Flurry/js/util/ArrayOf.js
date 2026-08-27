// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

/**
 * Creates an array wherein each element is an instance created from the given
 * prototype
 * @param {Function} proto Prototype to make an array of elements with
 * @param {Number} count Number of elements
 * @return {Array} Array of elements, each of the given type
 */
var ArrayOf = function(proto, count)
{
    var array = new Array(count);

    for (var i = 0; i < count; i++)
        array[i] = new proto();

    return array;
};

/**
 * Creates an array wherein each element is an equivalent of an Vector4 unsigned
 * int vector
 * @param count
 * @returns {Uint16Array[]}
 */
ArrayOf.Vector4I = function(count)
{
    var array = new Array(count);

    for (var i = 0; i < count; i++)
        array[i] = Vector4I();

    return array;
};

/**
 * Creates an array wherein each element is an equivalent of an Vector4 float
 * vector
 * @param count
 * @returns {Float32Array[]}
 */
ArrayOf.Vector4F = function(count)
{
    var array = new Array(count);

    for (var i = 0; i < count; i++)
        array[i] = Vector4F();

    return array;
};

ArrayOf.ByteMatrix2 = function(a, b)
{
    var matrix = new Array(a);

    for (var i = 0; i < a; i++)
        matrix[i] = new Uint8Array(b);

    return matrix;
};

ArrayOf.ByteMatrix3 = function(a, b, c)
{
    var matrix = new Array(a);

    for (var i = 0; i < a; i++)
    {
        matrix[i] = new Array(b);

        for (var j = 0; j < b; j++)
            matrix[i][j] = new Uint8Array(c);
    }

    return matrix;
};