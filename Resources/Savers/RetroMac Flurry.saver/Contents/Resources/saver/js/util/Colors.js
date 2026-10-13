// By Roy Curtis
// Based off original code from https://github.com/calumr/flurry

/**
 * Parses a HTML hex color string or plain integer into RGB components between 0 and 1
 * @param {string|number=} [value=0]
 * @returns {number[]}
 */
ColorC = function(value)
{
    var rgb = [];

    if (typeof value == 'string')
    {
        if (value[0] == '#')
            value = value.slice(1);

        value = parseInt(value, 16);
    }

    rgb[2] =  (value & 0xFF)      / 256;
    rgb[1] = ((value>>8) & 0xFF)  / 256;
    rgb[0] = ((value>>16) & 0xFF) / 256;
    return rgb;
};