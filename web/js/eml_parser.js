// Custom wrapper for eml-parse-js library to make it Flutter-friendly
window.ArDriveEmlParser = window.ArDriveEmlParser || {};

// Helper to wait for library and dependencies to load
window.ArDriveEmlParser.waitForLibrary = function(maxAttempts = 50, delayMs = 100) {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const checkLibrary = () => {
      // Check if both Base64 dependency and EmlParseJs are loaded
      if (typeof Base64 !== 'undefined' &&
          typeof EmlParseJs !== 'undefined' &&
          typeof EmlParseJs.readEml === 'function') {
        resolve();
      } else if (attempts >= maxAttempts) {
        const missing = [];
        if (typeof Base64 === 'undefined') missing.push('Base64');
        if (typeof EmlParseJs === 'undefined') missing.push('EmlParseJs');
        else if (typeof EmlParseJs.readEml !== 'function') missing.push('EmlParseJs.readEml');
        reject(new Error('Required libraries failed to load: ' + missing.join(', ') + ' (waited ' + (maxAttempts * delayMs) + 'ms)'));
      } else {
        attempts++;
        setTimeout(checkLibrary, delayMs);
      }
    };
    checkLibrary();
  });
};

window.ArDriveEmlParser.parseEml = function(emlContent) {
  return new Promise(async (resolve, reject) => {
    try {
      // Wait for library to be loaded if not already available
      await window.ArDriveEmlParser.waitForLibrary();

      // Parse using eml-parse-js library
      EmlParseJs.readEml(emlContent, function(error, parsed) {
        if (error) {
          resolve({
            success: false,
            error: error.message || 'Failed to parse EML file',
          });
          return;
        }

        try {
          // Extract and structure data for Flutter
          // Convert Date objects to ISO strings for Dart compatibility
          let dateString = '';
          if (parsed.date) {
            if (parsed.date instanceof Date) {
              dateString = parsed.date.toISOString();
            } else if (typeof parsed.date === 'string') {
              dateString = parsed.date;
            } else {
              dateString = String(parsed.date);
            }
          }

          const result = {
            success: true,
            headers: {
              from: window.ArDriveEmlParser.extractEmailAddress(parsed.from),
              to: window.ArDriveEmlParser.extractEmailAddress(parsed.to),
              cc: window.ArDriveEmlParser.extractEmailAddress(parsed.cc),
              subject: parsed.subject || '',
              date: dateString,
            },
            body: {
              text: parsed.text || '',
              html: parsed.html || '',
            },
            attachments: window.ArDriveEmlParser.extractAttachments(parsed.attachments || []),
          };

          resolve(result);
        } catch (extractError) {
          resolve({
            success: false,
            error: extractError.message || 'Failed to extract email data',
          });
        }
      });
    } catch (error) {
      resolve({
        success: false,
        error: error.message || 'Failed to parse EML file',
      });
    }
  });
};

/**
 * Extract email addresses from various formats
 */
window.ArDriveEmlParser.extractEmailAddress = function(field) {
    if (!field) return '';
    if (typeof field === 'string') return field;
    if (Array.isArray(field)) {
      return field.map(item => {
        if (typeof item === 'string') return item;
        if (item.email) return item.name ? `${item.name} <${item.email}>` : item.email;
        return '';
      }).filter(Boolean).join(', ');
    }
    if (field.email) return field.name ? `${field.name} <${field.email}>` : field.email;
    return '';
  };

/**
 * Extract and structure attachment data
 */
window.ArDriveEmlParser.extractAttachments = function(attachments) {
    if (!attachments) return [];

    return attachments.map((att, index) => {
      // Determine content type
      let contentType = att.contentType || att.mimeType || 'application/octet-stream';

      // Extract filename
      let filename = att.name || att.filename || `attachment_${index + 1}`;

      // eml-parse-js provides data64 which is already base64-encoded
      let base64Data = att.data64 || '';

      // Calculate size from base64 string (rough estimate)
      // Each base64 char represents 6 bits, so 4 chars = 3 bytes
      let size = base64Data ? Math.floor((base64Data.length * 3) / 4) : 0;

      return {
        filename: filename,
        contentType: contentType,
        size: size,
        data: base64Data,
        id: att.id || att.cid || `att_${index}`,
      };
    });
  };
