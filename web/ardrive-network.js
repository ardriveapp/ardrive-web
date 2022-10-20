async function getJson(url) {
  try {
    const response = await fetch(url, {
      method: 'GET',
      mode: 'cors',
      headers: {
        Accept: 'application/json',
      },
    });
    const responseJson = await response.json();
    return {
      statusCode: response.status,
      reasonPhrase: response.statusText,
      jsonResponse: responseJson,
    };
  } catch (error) {
    return { err: error };
  }
}
