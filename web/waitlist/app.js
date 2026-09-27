(function () {
  const form = document.getElementById("waitlist-form");
  const status = document.getElementById("form-status");
  const button = form.querySelector("button[type=submit]");
  const { supabaseUrl, supabaseKey } = window.MORNING_WAVE_CONFIG;

  // Which community or video sent the visitor, e.g. ?ref=reddit-agingparents
  const params = new URLSearchParams(location.search);
  const ref = params.get("ref") || params.get("utm_source") || "";
  // Array.from so an emoji at the 64-character cut isn't split in half.
  const source = Array.from(ref).slice(0, 64).join("") || null;

  function show(message, isError) {
    status.textContent = message;
    status.classList.toggle("error", isError);
  }

  async function saveSignup(row) {
    const res = await fetch(supabaseUrl + "/rest/v1/waitlist", {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify(row),
    });
    // 409 means this email is already on the list, which is fine.
    if (res.ok || res.status === 409) return;
    // 400 is the database refusing the row, most likely the email address.
    throw new Error(res.status === 400 ? "rejected" : "Signup failed: " + res.status);
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = new FormData(form);

    if (data.get("website")) return;
    if (!form.checkValidity()) {
      show("Please enter your email and answer both questions.", true);
      form.reportValidity();
      return;
    }

    button.disabled = true;
    show("Adding you…", false);
    try {
      await saveSignup({
        email: data.get("email").trim(),
        own_phone: data.get("own_phone"),
        parent_phone: data.get("parent_phone"),
        source,
      });
      form.reset();
      show("You’re on the list. We’ll email you when Morning Wave is ready.", false);
    } catch (err) {
      console.error(err);
      show(err.message === "rejected"
        ? "That email address doesn’t look right. Please check it."
        : "Something went wrong. Please try again in a minute.", true);
    } finally {
      button.disabled = false;
    }
  });
})();
