.pragma library
.import "MarketModel.js" as MarketModel

// Painting and inspection share the same filtered samples and coordinates.
function samples(points, timestamps) {
  var result = [];
  if (!MarketModel.isArray(points)) return result;
  var paired = MarketModel.isArray(timestamps) && timestamps.length === points.length;
  var timed = paired;
  var previous = null;
  for (var i = 0; i < points.length; i += 1) {
    var value = MarketModel.finiteNumber(points[i]);
    if (value === null) continue;
    var time = paired ? MarketModel.timestampMilliseconds(timestamps[i]) : null;
    if (time === null || (previous !== null && time <= previous)) timed = false;
    result.push({ value: value, time: time, position: 0 });
    previous = time;
  }
  var span = result.length > 1 ? result[result.length - 1].time - result[0].time : 0;
  for (var j = 0; j < result.length; j += 1) {
    result[j].position = timed && span > 0 ? (result[j].time - result[0].time) / span
      : (result.length > 1 ? j / (result.length - 1) : 0.5);
  }
  return result;
}

function bounds(samples, reference) {
  if (samples.length === 0) return { minimum: 0, spread: 1 };
  var minimum = samples[0].value;
  var maximum = minimum;
  for (var i = 1; i < samples.length; i += 1) {
    minimum = Math.min(minimum, samples[i].value);
    maximum = Math.max(maximum, samples[i].value);
  }
  var referenceValue = MarketModel.finiteNumber(reference);
  if (referenceValue !== null) {
    minimum = Math.min(minimum, referenceValue);
    maximum = Math.max(maximum, referenceValue);
  }
  var spread = maximum - minimum;
  if (spread <= 0) spread = Math.max(Math.abs(maximum) * 0.01, 1);
  return { minimum: minimum, spread: spread };
}

function nearest(samples, position) {
  if (samples.length === 0 || !isFinite(position)) return -1;
  var index = 0;
  for (var i = 1; i < samples.length; i += 1) {
    if (Math.abs(samples[i].position - position) < Math.abs(samples[index].position - position)) index = i;
  }
  return index;
}

function timestampLabel(time) {
  if (time === null) return "Time unavailable";
  var date = new Date(time);
  if (!isFinite(date.getTime())) return "Time unavailable";
  return date.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, " UTC");
}
