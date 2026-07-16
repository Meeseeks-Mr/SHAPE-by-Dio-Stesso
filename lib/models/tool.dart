/// Active creation tool / orb context — drives §10 Contextual Selection.
enum ActiveTool { none, pen, draw, text }

/// Which contextual sheet is currently presented in the bottom-sheet host
/// (§12). `none` means the canvas is unobstructed.
enum ActiveSheet {
  none,
  fill,
  effects,
  layers,
  shapes,
  align,
  typography,
  crop,
  shapeParams,
  strokes,
  blendSteps,
  blendModes,
  repeat,
  export
}
