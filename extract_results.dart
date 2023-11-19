import 'dart:io';

// script to extract benchmark results and update readme.md

final langRegex = RegExp(r'^[a-zA-Z]');
final colonOrNewLineRegex = RegExp(r'[:\n]');
final pTimeRegex = RegExp(r'Processing time[^0-9]*([\d.]+)\s?(ms|s|milliseconds)');
final tTimeRegex = RegExp(r'Time[^0-9]*([\d.]+ (ms|s))');
final memUsageRegex = RegExp(r'memory: (\d+)k');

const multiCoreHeading = '''
### Multicore Results

| Language       | Time (5k posts) | 20k posts        | 60k posts        | Total     |
| -------------- | --------------- | ---------------- | ---------------- | --------- |
''';

const memUsageHeading = '''
### Memory Usage Results

| Language | 5k posts | 20k posts | 60k posts | Total |
| -------- | -------- | --------- | --------- | ----- |
''';

void main(List<String> args) {
  final filename = args.firstOrNull;

  if (filename == null) return print('Usage: extract <filename>');

  final file = File(filename);

  if (!file.existsSync()) return print('File "$filename" not found');

  final lines = file.readAsLinesSync();

  final scores = <String, List<Score>>{};

  Score? currentScore;
  String? currentLang;

  for (final line in lines) {
    if (langRegex.hasMatch(line)) {
      final name = line.trim().replaceAll(colonOrNewLineRegex, '');

      if (scores.containsKey(name)) {
        if (currentLang != name) {
          final newScore = Score(name: name);
          scores[name]!.add(newScore);
          currentScore = newScore;
          currentLang = name;
          continue;
        } else {
          currentScore = scores[name]!.last;
          continue;
        }
      }

      final newScore = Score(name: name);
      scores[name] = [newScore];
      currentScore = newScore;
      currentLang = name;
      continue;
    }

    if (currentScore == null) {
      continue;
    }

    final processTimeMatch = pTimeRegex.firstMatch(line);

    if (processTimeMatch != null) {
      final unit = processTimeMatch.group(2)!.replaceFirst('milliseconds', 'ms');
      final time = double.parse(processTimeMatch.group(1)!.trim());
      currentScore.addTime(time, unit);
      continue;
    }

    final memUsageMatches = memUsageRegex.firstMatch(line);

    if (memUsageMatches != null) {
      final memUsage = int.parse(memUsageMatches.group(1)!);
      currentScore.addMemoryUsage(memUsage);
      continue;
    }
  }

  final sortedScores = scores.values.toList()
    ..sort((a, b) {
      final aSum = a.fold(0.0, (total, sc) => sc.avgTimeMS() + total);
      final bSum = b.fold(0.0, (total, sc) => sc.avgTimeMS() + total);
      return aSum.compareTo(bSum);
    });

  final sortedMemScores = scores.values.toList()
    ..sort((a, b) {
      final aSum = a.fold(0.0, (total, sc) => sc.avgMemUsage() + total);
      final bSum = b.fold(0.0, (total, sc) => sc.avgMemUsage() + total);
      return aSum.compareTo(bSum);
    });

  if (args.length > 1) {
    sortedScores.forEach(print);
  }

  final multiCoreScores = sortedScores.where((s) => s.first.name.contains('Concurrent')).toList();

  sortedScores..removeWhere((s) => s.first.name.contains('Concurrent'));

  if (sortedScores.first.length != 3) {
    sortedScores.forEach(print);
    sortedMemScores.forEach(print);
    print('${file.readAsStringSync()}\n\nEnough scores not found. Need 3 scores for each language to update readme.md');
    return;
  }

  final readmePathList = file.absolute.path.split(Platform.pathSeparator)
    ..removeLast()
    ..add('readme.md');

  final readmeFile = File(readmePathList.join('/'));

  if (!readmeFile.existsSync()) return print('$readmeFile not found');

  final readmeLines = readmeFile.readAsLinesSync();

  var shouldReplace = false;
  var replaced = false;

  final newReadmeContent = readmeLines
      .map((line) {
        if (line.startsWith('| -----') && !replaced && !shouldReplace) {
          shouldReplace = true;
          return line;
        }

        if (!shouldReplace) return line;

        // removes every line between the table heading and details open tag
        if (!line.trim().contains('<details>')) return null;

        shouldReplace = false;
        replaced = true;

        final sCoreLines = sortedScores.map((e) => e.toRowString()).join('\n') + '\n\n';
        final mCoreLines = multiCoreScores.map((e) => e.toRowString()).join('\n') + '\n\n';
        final memUsageLines = sortedMemScores.map((e) => e.toRowString(true)).join('\n') + '\n\n';

        // add back the line with detail opening tag
        return sCoreLines + multiCoreHeading + mCoreLines + memUsageHeading + memUsageLines + line;
      })
      .whereType<String>()
      .join('\n');

  readmeFile.writeAsStringSync(newReadmeContent);
}

typedef Time = ({double time, String unit});

class Score {
  final String name;
  final List<Time> processingTimes = [];
  final List<int> memoryUsages = [];

  Score({
    required this.name,
  });

  double avgTimeMS() {
    // if (processingTimes.isEmpty) throw Exception('No processing time found for $name');
    if (processingTimes.isEmpty) return double.maxFinite;

    return processingTimes.fold(0.0, (total, el) => el.millis + total) / processingTimes.length;
  }

  double avgMemUsage() {
    if (memoryUsages.isEmpty) return double.maxFinite;

    return memoryUsages.fold(0, (total, el) => el + total) / memoryUsages.length;
  }

  String avgTimeString() {
    final avg = avgTimeMS();

    if (avg >= double.maxFinite) return 'OOM';

    if (avg < 1000) return avgTimeMS().toStringAsFixed(2) + ' ms';

    return (avg / 1000).toStringAsFixed(2) + ' s';
  }

  String avgMemUsageString() {
    if (avgTimeMS() >= double.maxFinite) return 'OOM';

    return (avgMemUsage() / 1000).toStringAsFixed(2) + ' MB';
  }

  void addTime(double time, String unit) {
    processingTimes.add((time: time, unit: unit));
  }

  void addMemoryUsage(int memUsage) {
    memoryUsages.add(memUsage);
  }

  @override
  String toString() {
    return '| $name | ${avgTimeString()}  |';
  }

  String toMemUsageString() {
    return '| $name | ${avgMemUsageString()}  |';
  }
}

// var min5k = double.maxFinite;
// var min20k = double.maxFinite;
// var min60k = double.maxFinite;

extension on List<Score> {
  String toRowString([bool isMemUsage = false]) {
    var name = first.name == "Julia HO" ? "_Julia HO_[^1]" : first.name;

    if (name == 'Julia HO') {
      name = '_Julia HO_[^1]';
    } else if (name == 'Inko') {
      name = 'Inko[^2]';
    }

    return isMemUsage
        ? '| ${name} | ${first.avgMemUsageString()} | ${this[1].avgMemUsageString()} | ${this[2].avgMemUsageString()} | ${this.totalMemString} |'
        : '| ${name} | ${first.avgTimeString()} | ${this[1].avgTimeString()} | ${this[2].avgTimeString()} | ${this.totalString} |';
  }

  String get totalString {
    if (this[2].avgTimeString() == 'OOM') return 'N/A';

    final sum = fold(0.0, (total, sc) => sc.avgTimeMS() + total);

    if (sum < 1000) return sum.toStringAsFixed(2) + ' ms';

    return (sum / 1000).toStringAsFixed(2) + ' s';
  }

  String get totalMemString {
    if (this[2].avgMemUsageString() == 'OOM') return 'N/A';

    final sum = fold(0.0, (total, sc) => sc.avgMemUsage() + total);

    return (sum / 1000).toStringAsFixed(2) + ' MB';
  }
}

extension on Time {
  double get millis => unit == 'ms' ? time : time * 1000;
}
