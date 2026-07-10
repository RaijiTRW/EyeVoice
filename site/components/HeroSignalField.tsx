"use client";

import { useEffect, useRef } from "react";

const VERTEX_SHADER = `
  attribute vec2 a_position;

  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
  }
`;

const FRAGMENT_SHADER = `
  precision highp float;

  uniform vec2 u_resolution;
  uniform vec2 u_pointer;
  uniform float u_time;

  float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
  }

  vec2 hash22(vec2 p) {
    float n = sin(dot(p, vec2(41.0, 289.0)));
    return fract(vec2(262144.0, 32768.0) * n);
  }

  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
      mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
      mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x),
      f.y
    );
  }

  float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.52;
    mat2 turn = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 4; i++) {
      value += amplitude * noise(p);
      p = turn * p * 2.03 + vec2(7.13, 3.71);
      amplitude *= 0.49;
    }
    return value;
  }

  // Distance between the two nearest moving sites. Near-zero values trace
  // the fine, irregular boundaries of a refractive Voronoi field.
  float voronoiEdge(vec2 p, float timeOffset) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    float nearest = 8.0;
    float secondNearest = 8.0;

    for (int y = -1; y <= 1; y++) {
      for (int x = -1; x <= 1; x++) {
        vec2 neighbor = vec2(float(x), float(y));
        vec2 site = hash22(cell + neighbor);
        site = 0.5 + 0.42 * sin(timeOffset + 6.2831 * site);
        vec2 delta = neighbor + site - local;
        float distanceSquared = dot(delta, delta);

        if (distanceSquared < nearest) {
          secondNearest = nearest;
          nearest = distanceSquared;
        } else if (distanceSquared < secondNearest) {
          secondNearest = distanceSquared;
        }
      }
    }

    return sqrt(secondNearest) - sqrt(nearest);
  }

  void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;
    float aspect = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 pointer = (u_pointer - 0.5) * vec2(0.065, 0.045);
    float fieldCenterY = u_resolution.x < 500.0 ? 0.83 : 0.80;
    vec2 p = uv - vec2(0.5, fieldCenterY) - pointer;
    p.x *= aspect;

    float t = u_time * 0.16;

    // Two-stage domain warping removes any obvious primitive shape. The
    // pointer bends the whole optical field, like moving a lens over film.
    float flowA = fbm(p * 1.28 + vec2(t, -t * 0.72));
    float flowB = fbm(p * 1.63 + vec2(-t * 0.56, t * 0.91) + flowA * 2.4);
    vec2 warp = vec2(flowA - 0.5, flowB - 0.5);
    vec2 warped = p + warp * 0.42;
    warped += 0.035 * vec2(
      sin(warped.y * 9.0 + t * 4.0),
      cos(warped.x * 7.0 - t * 3.0)
    );

    // Offset caustic layers drift at different scales. Their overlap creates
    // a changing, crystalline network rather than concentric animation.
    float edgeA = voronoiEdge(warped * 3.15 + vec2(t * 0.42, -t * 0.18), t * 1.7);
    mat2 skew = mat2(0.86, -0.52, 0.52, 0.86);
    float edgeB = voronoiEdge(
      skew * warped * 4.85 + vec2(-t * 0.25, t * 0.31),
      2.1 - t * 1.2
    );
    float causticA = 1.0 - smoothstep(0.012, 0.074, edgeA);
    float causticB = 1.0 - smoothstep(0.009, 0.052, edgeB);
    causticA *= causticA;
    causticB *= causticB;

    // Difference between two turbulent volumes reveals hairline filaments.
    float volumeA = fbm(warped * 2.55 + vec2(t * 0.34, 4.2));
    float volumeB = fbm(skew * warped * 2.75 - vec2(t * 0.29, 1.7));
    float foldDistance = abs(volumeA - volumeB);
    float filaments = 1.0 - smoothstep(0.008, 0.072, foldDistance);
    filaments = filaments * filaments * (0.55 + 0.45 * flowB);

    // An uneven, turbulent envelope keeps the field concentrated around the
    // mark while letting a few strands escape into the negative space.
    vec2 envelopePoint = vec2(p.x * 0.62, p.y * 1.28);
    float envelopeNoise = fbm(p * 1.07 - vec2(t * 0.18, t * 0.11));
    float envelope = smoothstep(
      0.84,
      0.08,
      length(envelopePoint) + (envelopeNoise - 0.5) * 0.48
    );
    float innerCut = smoothstep(
      0.12,
      0.42,
      length(vec2(p.x * 0.62, p.y * 1.08))
    );

    // Sparse addressable sparks suggest data passing through the organic
    // field. They are grid-aligned but displaced by the same fluid warp.
    vec2 sparkGrid = (uv + warp * 0.025) * vec2(92.0, 54.0);
    vec2 sparkCell = floor(sparkGrid);
    vec2 sparkLocal = abs(fract(sparkGrid) - 0.5);
    float sparkSeed = hash(sparkCell);
    float sparkPulse = 0.5 + 0.5 * sin(u_time * 2.2 + sparkSeed * 18.0);
    float sparkShape = 1.0 - smoothstep(0.05, 0.16, max(sparkLocal.x, sparkLocal.y));
    float sparks = step(0.978, sparkSeed) * sparkShape * pow(sparkPulse, 10.0) * envelope;

    float softVolume = smoothstep(0.28, 0.82, volumeA * 0.58 + volumeB * 0.54);
    float grain = hash(gl_FragCoord.xy + floor(u_time * 10.0)) - 0.5;
    float viewportVignette = smoothstep(
      0.92,
      0.16,
      length((uv - 0.5) * vec2(0.74, 1.0))
    );

    vec3 graphite = vec3(0.34, 0.39, 0.42);
    vec3 silver = vec3(0.74, 0.82, 0.86);
    vec3 pink = vec3(1.0, 0.31, 0.64);
    vec3 color = graphite * softVolume * 0.075;
    color += silver * (causticA * 0.18 + filaments * 0.19);
    color += pink * (causticB * 0.14 + filaments * causticA * 0.09);
    color += mix(silver, pink, sparkSeed) * sparks * 0.42;
    color += vec3(grain * 0.014);

    color *= envelope * innerCut * viewportVignette;
    float alpha = clamp(max(max(color.r, color.g), color.b), 0.0, 0.38);
    gl_FragColor = vec4(color, alpha);
  }
`;

function createShader(
  gl: WebGLRenderingContext,
  type: number,
  source: string,
) {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

export default function HeroSignalField() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const gl = canvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      depth: false,
      powerPreference: "high-performance",
      premultipliedAlpha: true,
    });
    if (!gl) return;

    const vertex = createShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
    const fragment = createShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
    if (!vertex || !fragment) return;

    const program = gl.createProgram();
    if (!program) return;
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
    gl.useProgram(program);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      gl.STATIC_DRAW,
    );

    const position = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    const resolution = gl.getUniformLocation(program, "u_resolution");
    const pointerLocation = gl.getUniformLocation(program, "u_pointer");
    const time = gl.getUniformLocation(program, "u_time");
    const pointer = { x: 0.5, y: 0.5 };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      const renderScale = rect.width < 640 ? 0.55 : 0.65;
      const dpr = Math.min(window.devicePixelRatio || 1, renderScale);
      const width = Math.max(1, Math.round(rect.width * dpr));
      const height = Math.max(1, Math.round(rect.height * dpr));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
        gl.viewport(0, 0, width, height);
      }
    };

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointer.x = (event.clientX - rect.left) / rect.width;
      pointer.y = 1 - (event.clientY - rect.top) / rect.height;
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(canvas);
    window.addEventListener("pointermove", onPointerMove, { passive: true });
    resize();

    let frame = 0;
    let stopped = false;
    let previousFrame = 0;
    const render = (milliseconds: number) => {
      if (stopped) return;
      if (!reducedMotion && milliseconds - previousFrame < 1000 / 30) {
        frame = requestAnimationFrame(render);
        return;
      }
      previousFrame = milliseconds;
      gl.uniform2f(resolution, canvas.width, canvas.height);
      gl.uniform2f(pointerLocation, pointer.x, pointer.y);
      gl.uniform1f(time, reducedMotion ? 0 : milliseconds / 1000);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      if (!reducedMotion) frame = requestAnimationFrame(render);
    };
    frame = requestAnimationFrame(render);

    return () => {
      stopped = true;
      cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      window.removeEventListener("pointermove", onPointerMove);
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
      gl.deleteShader(vertex);
      gl.deleteShader(fragment);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="hero-signal-field"
      aria-hidden="true"
    />
  );
}
