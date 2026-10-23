// Mirror of shared/detector_params.json (checked by test/imaging/params_test.dart).
abstract final class DetectorParams {
  static const maxDim = 500;
  static const pad = 4;
  static const minAreaRatio = 0.08;
  static const minFillRatio = 0.85;
  static const maxEdgeDeviation = 0.025;
  static const minAngle = 35.0;
  static const maxAngle = 145.0;
  static const approxEpsilons = [0.02, 0.03, 0.04];
  static const claheClip = 3.0;
  static const lowCanny = [12, 36];
  static const refineBands = [10, 5, 3];
  static const refineMinGrad = 20.0;

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
  };
}
