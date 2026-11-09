/* Device diagnosis aid (2026-11-09, docs/SERVER.md "client_log"). Loaded by the export's head_include BEFORE the engine runs
 * (tools/export_web.sh copies it to build/web/diag.js). It only observes: it keeps the last lines of console.error, GL-related
 * console.warn, window errors and rejections, plus the failed shader compiles / program links it sees, and a reference to the
 * engine's own WebGL context (getContext is wrapped to remember it, never to create one). game/telemetry.gd reads
 * window.__scDiag.snapshot() and sends it as a "client_log" event. */
(function () {
	if (window.__scDiag) return;
	var MAX_LINES = 40, MAX_LINE = 400, MAX_TOTAL = 16384;
	var D = window.__scDiag = { lines: [], ctx: null, ctx_kind: '', lost: 0, seq: 0, t0: Date.now(), dropped: 0 };
	var GLRE = /webgl|shader|glsl|gl_|framebuffer|texture|invalid_|context|compile|link|opengl|adreno|vertex|fragment|uniform|sampler/i;

	function add(lvl, msg) {
		try {
			msg = String(msg == null ? '' : msg);
			D.seq++;
			if (msg.length > MAX_LINE) msg = msg.slice(0, MAX_LINE - 3) + '...';
			for (var i = 0; i < D.lines.length; i++) {
				if (D.lines[i].m === msg && D.lines[i].l === lvl) { D.lines[i].n++; D.lines[i].t = Math.round(performance.now()); return; }
			}
			D.lines.push({ t: Math.round(performance.now()), l: lvl, n: 1, m: msg });
			if (D.lines.length > MAX_LINES) { D.lines.shift(); D.dropped++; }
		} catch (e) { /* never break the page */ }
	}
	D.add = add;
	function fmt(args) {
		var out = [];
		for (var i = 0; i < args.length; i++) {
			var a = args[i];
			try { out.push(typeof a === 'string' ? a : (a && a.stack ? a.stack : (typeof a === 'object' ? JSON.stringify(a) : String(a)))); }
			catch (e) { out.push(String(a)); }
		}
		return out.join(' ');
	}
	var oe = console.error, ow = console.warn;
	console.error = function () { add('E', fmt(arguments)); return oe.apply(console, arguments); };
	console.warn = function () {
		var s = fmt(arguments);
		if (GLRE.test(s)) add('W', s);
		return ow.apply(console, arguments);
	};
	window.addEventListener('error', function (e) {
		add('X', (e.message || 'error') + ' @' + String(e.filename || '').split('/').pop() + ':' + (e.lineno || 0));
	});
	window.addEventListener('unhandledrejection', function (e) {
		var r = e.reason; add('R', (r && r.message) || r);
	});

	// Remember the engine's WebGL context; never create one.
	var gc = HTMLCanvasElement.prototype.getContext;
	HTMLCanvasElement.prototype.getContext = function (kind) {
		var c = gc.apply(this, arguments);
		try {
			if (c && (kind === 'webgl2' || kind === 'webgl' || kind === 'experimental-webgl') && !D.ctx && this.id === 'canvas') {
				D.ctx = c; D.ctx_kind = kind;
				this.addEventListener('webglcontextlost', function () { D.lost++; add('X', 'webglcontextlost'); });
				this.addEventListener('webglcontextrestored', function () { add('X', 'webglcontextrestored'); });
			}
		} catch (e) { }
		return c;
	};
	// Failed compiles and links (the driver's own log), in case the engine's error text is cut.
	function wrapGL(proto) {
		if (!proto) return;
		var gsp = proto.getShaderParameter, gpp = proto.getProgramParameter;
		proto.getShaderParameter = function (sh, p) {
			var r = gsp.apply(this, arguments);
			try { if (p === this.COMPILE_STATUS && !r) add('S', 'compile failed: ' + String(this.getShaderInfoLog(sh)).replace(/\s+/g, ' ')); } catch (e) { }
			return r;
		};
		proto.getProgramParameter = function (pr, p) {
			var r = gpp.apply(this, arguments);
			try { if (p === this.LINK_STATUS && !r) add('S', 'link failed: ' + String(this.getProgramInfoLog(pr)).replace(/\s+/g, ' ')); } catch (e) { }
			return r;
		};
	}
	wrapGL(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);
	wrapGL(window.WebGLRenderingContext && WebGLRenderingContext.prototype);

	// The context's parameters, read from the engine's own context (one read per page).
	D.glParams = function () {
		if (D.gl_cache) return D.gl_cache;
		var g = D.ctx;
		if (!g) return { ctx: 'none' };
		var o = { ctx: D.ctx_kind };
		try {
			var names = ['MAX_TEXTURE_SIZE', 'MAX_VERTEX_TEXTURE_IMAGE_UNITS', 'MAX_TEXTURE_IMAGE_UNITS', 'MAX_COMBINED_TEXTURE_IMAGE_UNITS',
				'MAX_VARYING_VECTORS', 'MAX_FRAGMENT_UNIFORM_VECTORS', 'MAX_VERTEX_UNIFORM_VECTORS', 'MAX_VERTEX_ATTRIBS',
				'MAX_RENDERBUFFER_SIZE', 'MAX_DRAW_BUFFERS', 'MAX_SAMPLES', 'MAX_UNIFORM_BLOCK_SIZE', 'MAX_ARRAY_TEXTURE_LAYERS',
				'DEPTH_BITS', 'STENCIL_BITS', 'SAMPLES', 'RENDERER', 'VENDOR', 'VERSION', 'SHADING_LANGUAGE_VERSION'];
			for (var i = 0; i < names.length; i++) {
				var k = names[i];
				try { var v = g.getParameter(g[k]); if (v !== undefined && g[k] !== undefined) o[k] = typeof v === 'object' && v !== null ? String(v) : v; } catch (e) { }
			}
			var ex = g.getSupportedExtensions() || [];
			o.ext_n = ex.length;
			o.EXT_color_buffer_float = ex.indexOf('EXT_color_buffer_float') >= 0 ? 1 : 0;
			o.OES_texture_float_linear = ex.indexOf('OES_texture_float_linear') >= 0 ? 1 : 0;
			o.EXT_texture_filter_anisotropic = ex.indexOf('EXT_texture_filter_anisotropic') >= 0 ? 1 : 0;
			try {
				var a = g.getContextAttributes();
				if (a) { o.attr_stencil = a.stencil ? 1 : 0; o.attr_depth = a.depth ? 1 : 0; o.attr_antialias = a.antialias ? 1 : 0; o.attr_alpha = a.alpha ? 1 : 0; }
			} catch (e) { }
			try {
				var d = g.getExtension('WEBGL_debug_renderer_info');
				if (d) o.UNMASKED_RENDERER = String(g.getParameter(d.UNMASKED_RENDERER_WEBGL));
			} catch (e) { }
			D.gl_cache = o;
		} catch (e) { o.err = String(e); }
		return o;
	};

	// JSON for a client_log event: newest lines first until the budget (16 KB) is used, returned oldest first.
	D.snapshot = function (withGl) {
		var out = { seq: D.seq, lines: [], lines_total: D.lines.length, dropped: D.dropped, ctx_lost: D.lost, up_s: Math.round((Date.now() - D.t0) / 1000) };
		if (withGl) out.gl = D.glParams();
		var used = JSON.stringify(out).length;
		for (var i = D.lines.length - 1; i >= 0; i--) {
			var s = JSON.stringify(D.lines[i]).length + 1;
			if (used + s > MAX_TOTAL - 200) break;
			out.lines.unshift(D.lines[i]); used += s;
		}
		return JSON.stringify(out);
	};
})();
