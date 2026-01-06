
const { error, time } = require('console');
const https = require('https');
const { URL } = require('url');

class SplunkLogger {
  constructor({ url, token, index, sourcetype, environment }) {
    this.splunkUrl = new URL(url);
    this.token = token;
    this.index = index;
    this.sourcetype = sourcetype;
    this.environment = environment;
    this.events = [];
  }

log(input) {
  const { message, logGroup, logStream } = input;

  this.events.push({
    event: message,
    index: this.index,
    sourcetype: this.sourcetype,
    source: logStream || 'unknown',
    host: this.environment,
    time: Date.now() / 1000,
    fields: {
      logGroup,
      logStream
    }
  });
}

  flushAsync(callback) {
    if (this.events.length === 0) {
      return callback(null, { statusCode: 204, message: 'No events to send' });
    }

    const payload = JSON.stringify(this.events);
    const options = {
      hostname: this.splunkUrl.hostname,
      port: this.splunkUrl.port || 443,
      path: '/services/collector/event',
      method: 'POST',
      headers: {
        'Authorization': `Splunk ${this.token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    };

    const req = https.request(options, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => callback(null, { statusCode: res.statusCode, body }));
    });

    req.on('error', err => callback(err));
    req.write(payload);
    req.end();
    this.events = [];
  }
}
module.exports = SplunkLogger;