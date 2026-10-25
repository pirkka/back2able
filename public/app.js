(function () {
  "use strict";

  var form = document.getElementById("convert-form");
  var fileInput = document.getElementById("file-input");
  var submitButton = document.getElementById("submit-button");
  var progress = document.getElementById("progress");
  var elapsed = document.getElementById("elapsed");
  var status = document.getElementById("status");

  var timer = null;

  var GENERIC_ERRORS = {
    413: "That file is too large.",
    429: "Too many conversions right now, please try again shortly.",
    503: "The server is busy, please try again in a minute.",
    502: "The server could not be reached, please try again shortly.",
    504: "The conversion took too long, please try again with a smaller project."
  };

  function errorMessage(response, text) {
    var generic = GENERIC_ERRORS[response.status] || "Something went wrong.";
    var trimmed = (text || "").trim();

    // The proxy answers with an HTML error page, which is not worth showing.
    if (!trimmed || trimmed.indexOf("<") !== -1) {
      return generic;
    }

    return trimmed;
  }

  function setStatus(message, kind) {
    status.textContent = message;
    status.className = "status " + kind;
    status.hidden = false;
  }

  function startProgress() {
    status.hidden = true;
    status.textContent = "";
    elapsed.textContent = "0";
    progress.hidden = false;
    submitButton.disabled = true;
    fileInput.disabled = true;

    var seconds = 0;
    timer = window.setInterval(function () {
      seconds += 1;
      elapsed.textContent = String(seconds);
    }, 1000);
  }

  function stopProgress() {
    if (timer) {
      window.clearInterval(timer);
      timer = null;
    }
    progress.hidden = true;
    submitButton.disabled = false;
    fileInput.disabled = false;
  }

  function outputFilename(response, source) {
    var disposition = response.headers.get("content-disposition") || "";
    var match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition);

    if (match) {
      try {
        return decodeURIComponent(match[1]);
      } catch (error) {
        return match[1];
      }
    }

    return source.name.replace(/\.als$/i, "_L11.als");
  }

  function download(blob, filename) {
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");

    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    window.setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 60000);
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();

    var file = fileInput.files[0];

    if (!file) {
      setStatus("Please choose an .als file first.", "error");
      return;
    }

    // Build the payload before disabling the inputs: disabled form controls are
    // not included in FormData.
    var data = new FormData(form);

    startProgress();

    fetch(form.action, { method: "POST", body: data })
      .then(function (response) {
        if (!response.ok) {
          return response.text().then(function (text) {
            throw new Error(errorMessage(response, text));
          });
        }

        return response.blob().then(function (blob) {
          return { blob: blob, filename: outputFilename(response, file) };
        });
      })
      .then(function (result) {
        stopProgress();
        setStatus("Processing finished. Downloading " + result.filename + "…", "success");
        download(result.blob, result.filename);
      })
      .catch(function (error) {
        stopProgress();
        setStatus("Conversion failed: " + error.message, "error");
      });
  });
})();
