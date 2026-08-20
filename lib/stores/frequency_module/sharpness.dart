enum Sharpness {
  veryFlat(
    minCents: double.negativeInfinity,
    maxCents: -35,
  ),

  flat(
    minCents: -35,
    maxCents: -15,
  ),

  slightlyFlat(
    minCents: -15,
    maxCents: 0,
  ),

  perfect(
    minCents: 0,
    maxCents: 0,
  ),

  slightlySharp(
    minCents: 0,
    maxCents: 15,
  ),

  sharp(
    minCents: 15,
    maxCents: 35,
  ),

  verySharp(
    minCents: 35,
    maxCents: double.infinity,
  );

  final double minCents;
  final double maxCents;

  const Sharpness({
    required this.minCents,
    required this.maxCents,
  });

  static Sharpness fromCents(double cents) {
    if (cents == 0) {
      return Sharpness.perfect;
    }

    return Sharpness.values.firstWhere(
          (sharpness) =>
      sharpness != Sharpness.perfect &&
          cents >= sharpness.minCents &&
          cents < sharpness.maxCents,
    );
  }
}
