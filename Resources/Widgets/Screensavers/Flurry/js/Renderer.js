/**
 * Renderer.js - Flurry.Renderer
 * Handles all the low level calls to WebGL
 */

/**
 * Creates a rendering handler, using the given canvas as output
 * @param {string} canvasId
 * @constructor
 */
Flurry.Renderer = function(canvasId)
{
    var contextParams = {
        preserveDrawingBuffer: true,
        depth: false, stencil: false,
        antialias: false
    };

    /**
     * Reference to the output canvas element
     * @type {HTMLCanvasElement}
     */
    this.canvas = document.getElementById(canvasId);

    /**
     * Core WebGL rendering context and methods
     * @type {WebGLRenderingContext}
     */
    this.gl = this.canvas.getContext('webgl', contextParams);

    if (!this.gl) throw new Error('Could not initialize WebGL');

    /**
     * All shaders used by the renderer
     * @type {WebGLShader[]}
     */
    this.shaders = [];

    /**
     * Attributes that link the arrays and shader data
     */
    this.attributes = {
        position : null,
        color    : null,
        uv       : null
    };

    /**
     * Uniforms that link const data to shaders
     */
    this.uniforms = {
        projMatrix      : {id : 0, matrix: new Float32Array(16)},
        modelViewMatrix : {id : 0, matrix: new Float32Array(16)},
        drawingRect     : {
            /** @type {WebGLUniformLocation} */
            id : 0,
            value: false
        }
    };

    /**
     * Buffers that link typed arrays to GL buffers
     */
    this.buffers = {
        position : {buffer : null, data : null},
        index    : {buffer : null, data : null},
        color    : {buffer : null, data : null},
        uv       : {buffer : null, data : null}
    };

    this.rect = {
        position : new Float32Array(8),
        color    : new Float32Array(16)
    };

    var gl = this.gl;

    this.blend = {
        from : gl.SRC_ALPHA,
        to   : gl.ONE,
        func : gl.FUNC_ADD
    };
    
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.CULL_FACE);
    gl.enable(gl.BLEND);
};

Flurry.Renderer.prototype.setup = function()
{
    var gl      = this.gl,
        program = gl.createProgram();

    this.shaders.forEach( function(s) { gl.attachShader(program, s); });
    gl.linkProgram(program);

    if ( !gl.getProgramParameter(program, gl.LINK_STATUS) )
        throw new Error( gl.getProgramInfoLog(program) );

    gl.useProgram(program);

    this.uniforms.projMatrix.id      = gl.getUniformLocation(program, 'projectionMatrix');
    this.uniforms.modelViewMatrix.id = gl.getUniformLocation(program, 'modelViewMatrix');
    this.uniforms.drawingRect.id     = gl.getUniformLocation(program, 'drawingRect');
    this.attributes.position = gl.getAttribLocation(program, "position");
    this.attributes.color    = gl.getAttribLocation(program, "color");
    this.attributes.uv       = gl.getAttribLocation(program, "uv");

    gl.enableVertexAttribArray(this.attributes.position);
    gl.enableVertexAttribArray(this.attributes.color);
    gl.enableVertexAttribArray(this.attributes.uv);
    this.resize();
    this.setFade(0.1);
};

Flurry.Renderer.prototype.render = function()
{
    var gl = this.gl;

    // Fade rect
    gl.blendEquation(gl.FUNC_ADD);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.uniform1i(this.uniforms.drawingRect.id, 1);
    gl.bindTexture(gl.TEXTURE_2D, null);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffers.position.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.rect.position, gl.STATIC_DRAW);
    gl.vertexAttribPointer(this.attributes.position, 2, gl.FLOAT, false, 0, 0);

    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffers.color.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.rect.color, gl.STATIC_DRAW);
    gl.vertexAttribPointer(this.attributes.color, 4, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4); // Causes a warning on first call due to unbound UV data

    // Flurry
    gl.blendEquation(this.blend.func);
    gl.blendFunc(this.blend.from, this.blend.to);
    gl.uniform1i(this.uniforms.drawingRect.id, 0);
    gl.bindTexture(gl.TEXTURE_2D, Flurry.Texture.ref);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffers.position.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.buffers.position.data, gl.DYNAMIC_DRAW);
    gl.vertexAttribPointer(this.attributes.position, 2, gl.FLOAT, false, 0, 0);

    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffers.color.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.buffers.color.data, gl.DYNAMIC_DRAW);
    gl.vertexAttribPointer(this.attributes.color, 4, gl.FLOAT, false, 0, 0);

    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffers.uv.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.buffers.uv.data, gl.DYNAMIC_DRAW);
    gl.vertexAttribPointer(this.attributes.uv, 2, gl.FLOAT, false, 0, 0);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.buffers.index.buffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, this.buffers.index.data, gl.DYNAMIC_DRAW);
    gl.drawElements(gl.TRIANGLES, MAX_SMOKE * 3 * 2, gl.UNSIGNED_SHORT, 0);
};

Flurry.Renderer.prototype.useShader = function(id)
{
    var gl           = this.gl,
        shaderScript = document.getElementById(id),
        shaderText   = shaderScript.innerHTML,
        shader;

    if (shaderScript.type == "x-shader/x-fragment")
        shader = gl.createShader(gl.FRAGMENT_SHADER);
    else if (shaderScript.type == "x-shader/x-vertex")
        shader = gl.createShader(gl.VERTEX_SHADER);
    else
        return null;

    gl.shaderSource(shader, shaderText);
    gl.compileShader(shader);

    if ( !gl.getShaderParameter(shader, gl.COMPILE_STATUS) )
        throw new Error( gl.getShaderInfoLog(shader) );
    else
        this.shaders.push(shader);
};

Flurry.Renderer.prototype.setBuffer = function(type, data)
{
    var gl = this.gl;

    this.buffers[type].buffer = gl.createBuffer();
    this.buffers[type].data   = data;
};

Flurry.Renderer.prototype.setFade = function(alpha)
{
    for (var i = 0; i < 4; i++)
        this.rect.color[i*4 + 3] = alpha;
};

Flurry.Renderer.prototype.setFadeColor = function(color)
{
    for (var i = 0; i < 4; i++)
    {
        this.rect.color[i*4]   = color[0];
        this.rect.color[i*4+1] = color[1];
        this.rect.color[i*4+2] = color[2];
    }
};

Flurry.Renderer.prototype.setBlendMode = function(mode)
{
    var gl = this.gl;
    switch (mode)
    {
        case BlendModes.Additive:
            this.blend.from = gl.SRC_ALPHA;
            this.blend.to   = gl.ONE;
            this.blend.func = gl.FUNC_ADD;
            break;
        case BlendModes.Multiply:
            this.blend.from = gl.ZERO;
            this.blend.to   = gl.SRC_COLOR;
            this.blend.func = gl.FUNC_ADD;
            break;
        case BlendModes.Normal:
            this.blend.from = gl.SRC_ALPHA;
            this.blend.to   = gl.ONE_MINUS_SRC_ALPHA;
            this.blend.func = gl.FUNC_ADD;
            break;
        case BlendModes.Subtract:
            this.blend.from = gl.ZERO;
            this.blend.to   = gl.ONE_MINUS_SRC_COLOR;
            this.blend.func = gl.FUNC_SUBTRACT;
            break;
    }
};

Flurry.Renderer.prototype.resize = function()
{
    console.log("[Renderer] Resizing...");
    var gl     = this.gl,
        width  = window.innerWidth,
        height = window.innerHeight;

    gl.viewport(0, 0, width, height);
    this.canvas.width  = width;
    this.canvas.height = height;

    this.rect.position.set([width, height, 0, height, width, 0, 0, 0]);

    //1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0
    mat4.ortho(this.uniforms.projMatrix.matrix, 0, width, 0, height, -1, 1);
    mat4.identity(this.uniforms.modelViewMatrix.matrix);
    gl.uniformMatrix4fv(this.uniforms.projMatrix.id, false, this.uniforms.projMatrix.matrix);
    gl.uniformMatrix4fv(this.uniforms.modelViewMatrix.id, false, this.uniforms.modelViewMatrix.matrix);
};