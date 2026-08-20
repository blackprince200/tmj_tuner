class IdRange {
  final double start;
  final double end;
  final String name;
  final String note;
  final double targetHz;


  final int startCents;
  final int bestCents;
  final int endCents;


  const IdRange({
    required this.start,
    required this.end,
    required this.name,
    required this.note,
    required this.targetHz,
    this.startCents=-5,
    this.bestCents=0,
    this.endCents=5
  });
}