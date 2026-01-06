const SplunkLogger = require('./lib/mysplunklogger');
const zlib = require('zlib');
const { GetSecretValueCommand, SecretsManagerClient } = require('@aws-sdk/client-secrets-manager');

const secretsClient = new SecretsManagerClient();
let logger = null;

async function getSecret(secretName) {
  const command = new GetSecretValueCommand({ SecretId: secretName });
  const result = await secretsClient.send(command);
  return result.SecretString;
}

async function initLogger() {
  const urlSecretName = process.env.SPLUNK_HEC_URL;     
  const tokenSecretName = process.env.SPLUNK_HEC_TOKEN;
  const indexName = process.env.SPLUNK_INDEX || "aws_loom"; 
  const sourcetypeName = process.env.SPLUNK_SOURCETYPE || "aws:loom:application";
  const environment = process.env.ENVIRONMENT || "unknown - refer logstream prefix to classify env names";

  const [url, token] = await Promise.all([
    getSecret(urlSecretName),
    getSecret(tokenSecretName)
  ]);

  logger = new SplunkLogger({ url, token, index: indexName, sourcetype: sourcetypeName, environment});
}

exports.handler = async (event, context, callback) => {
  try {
    if (!logger) await initLogger();

    const payload = Buffer.from(event.awslogs.data, 'base64');
    zlib.gunzip(payload, async (err, result) => {
      if (err) {
        console.error('Gzip error:', err);
        return callback(err);
      }

      let parsed;
      try {
        parsed = JSON.parse(result.toString('utf8'));
      } catch (parseErr) {
        console.error('JSON parse error:', parseErr);
        return callback(parseErr);
      }

      let count = 0;
      if (parsed.logEvents && Array.isArray(parsed.logEvents)) {
        parsed.logEvents.forEach(item => {
          logger.log({
            message: item.message,
            logGroup: parsed.logGroup,
            logStream: parsed.logStream
        });
          count++;
        });
      }

      logger.flushAsync((err, res) => {
        if (err) {
          console.error('Flush error:', err);
          return callback(err);
        }

        console.log(`Successfully sent ${count} log events to Splunk.`);
        callback(null, res);
      });
    });
  } catch (err) {
    console.error('Lambda error:', err);
    callback(err);
  }
};