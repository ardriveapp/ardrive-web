const retryStatusCodes = [
  408, 429, 440, 460, 499, 500, 502, 503, 504, 520, 521, 522, 523, 524, 525,
  527, 598, 599,
];

function retryDelay(attempt, retryDelayMS) {
  return parseInt(retryDelayMS * Math.pow(1.5, attempt));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function retry(url, retries, retryDelayMs, noLogs, retryAttempts) {
  await delay(retryDelay(retryAttempts, retryDelayMs));

  return await getJson([url, retries - 1, retryDelayMs, noLogs, retryAttempts]);
}

function formatLog(url, statusCode, statusMessage, retryAttempts) {
  return `uri: ${url}
  response: Http status error [${statusCode}]: ${statusMessage}
  retryAttempts: ${retryAttempts}`;
}

function isStatusCodeError(code) {
  return code >= 400 && code <= 599;
}

async function getJson(params) {
  const url = params[0];
  const retries = params[1];
  const retryDelayMs = params[2];
  const noLogs = params[3];
  let retryAttempts = params[4] ?? 0;

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
    });

    const statusCode = response.status;

    if (retries > 0 && retryStatusCodes.includes(statusCode)) {
      const log = formatLog(
        url,
        response.status,
        response.statusText,
        retryAttempts,
      );

      if (!noLogs) {
        console.warn(`Network Request Retry\n${log}`);
      }

      return await retry(url, retries, retryDelayMs, noLogs, retryAttempts + 1);
    } else {
      if (isStatusCodeError(statusCode)) {
        const log = formatLog(
          url,
          response.status,
          response.statusText,
          retryAttempts,
        );

        return {
          error: `Network Request Error\n${log}`,
          retryAttempts,
        };
      }
    }

    // if (retries === 0 || (retries === 0 && isStatusCodeError(statusCode))) {
    //   const log = formatLog(
    //     url,
    //     response.status,
    //     response.statusText,
    //     retryAttempts,
    //   );

    //   return {
    //     error: `Network Request Error\n${log}`,
    //     retryAttempts,
    //   };
    // }

    const data = await response.json();

    return {
      statusCode: response.status,
      statusMessage: response.statusText,
      data,
      retryAttempts,
    };
  } catch (error) {
    return { error, retryAttempts };
  }
}
