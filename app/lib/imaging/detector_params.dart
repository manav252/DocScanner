// Mirror of shared/detector_params.json (checked by test/imaging/params_test.dart).
abstract final class DetectorParams {
  static const maxDim = 500;
  static const pad = 4;
  static const minAreaRatio = 0.04;
  static const minFillRatio = 0.85;
  static const maxEdgeDeviation = 0.025;
  static const minAngle = 35.0;
  static const maxAngle = 145.0;
  static const approxEpsilons = [0.02, 0.03, 0.04];
  static const claheClip = 3.0;
  static const lowCanny = [12, 36];
  static const refineBands = [10, 5, 3];
  static const refineMinGrad = 20.0;
  static const maxBow = 0.12;
  static const curvedBow = 0.02;
  static const minSupport = 0.6;
  static const minLineSupport = 0.75;
  static const stepOffset = 3.0;
  static const stepMin = 10.0;
  static const lineCount = 8;
  static const confidentScore = 0.35;
  static const lineMinLength = 0.12;
  static const lineEpsilon = 0.005;
  static const frameMargin = 0.012;
  static const maxFrameSides = 2;
  static const maxArea = 0.95;
  static const frameSideFactor = 0.8;
  static const paperSatMax = 60;
  static const paperMorph = 0.02;
  static const glarePercentile = 99.0;
  static const textureMorph = 0.02;
  static const houghLines = 8;
  static const houghTilt = 20;
  static const houghVotes = 0.06;
  static const docRatios = [1.586, 1.414, 1.294];
  static const ratioTol = 0.05;
  static const ratioBonus = 1.15;
  static const trackMargin = 1.25;
  static const trackFullEvery = 5;

  static Map<String, Object> toJson() => {
    'max_dim': maxDim,
    'pad': pad,
    'min_area_ratio': minAreaRatio,
    'min_fill_ratio': minFillRatio,
    'max_edge_deviation': maxEdgeDeviation,
    'min_angle': minAngle,
    'max_angle': maxAngle,
    'approx_epsilons': approxEpsilons,
    'clahe_clip': claheClip,
    'low_canny': lowCanny,
    'refine_bands': refineBands,
    'refine_min_grad': refineMinGrad,
    'max_bow': maxBow,
    'curved_bow': curvedBow,
    'min_support': minSupport,
    'min_line_support': minLineSupport,
    'step_offset': stepOffset,
    'step_min': stepMin,
    'line_count': lineCount,
    'confident_score': confidentScore,
    'line_min_length': lineMinLength,
    'line_epsilon': lineEpsilon,
    'frame_margin': frameMargin,
    'max_frame_sides': maxFrameSides,
    'max_area': maxArea,
    'frame_side_factor': frameSideFactor,
    'paper_sat_max': paperSatMax,
    'paper_morph': paperMorph,
    'glare_percentile': glarePercentile,
    'texture_morph': textureMorph,
    'hough_lines': houghLines,
    'hough_tilt': houghTilt,
    'hough_votes': houghVotes,
    'doc_ratios': docRatios,
    'ratio_tol': ratioTol,
    'ratio_bonus': ratioBonus,
    'track_margin': trackMargin,
    'track_full_every': trackFullEvery,
  };
}
