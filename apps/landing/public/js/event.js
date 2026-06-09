/* Facteur — Page article : soirée de pré-lancement
 * Script autonome (indépendant de main.js).
 * Réutilise l'endpoint liste d'attente, puis révèle les boutons « Ajouter à l'agenda ».
 */

(function () {
    'use strict';

    var API_URL = 'https://facteur-production.up.railway.app';

    // ── UTM Capture (identique à main.js) ─────────
    var urlParams = new URLSearchParams(window.location.search);
    var utmData = {
        utm_source: urlParams.get('utm_source') || null,
        utm_medium: urlParams.get('utm_medium') || null,
        utm_campaign: urlParams.get('utm_campaign') || null,
    };

    var form = document.querySelector('.event-rsvp .waitlist-form');
    if (!form) return;

    var calendar = document.getElementById('event-calendar');

    function revealCalendar() {
        if (calendar) calendar.hidden = false;
    }

    form.addEventListener('submit', function (e) {
        e.preventDefault();

        var input = form.querySelector('.waitlist-form__input');
        var btn = form.querySelector('.waitlist-form__btn');
        var error = form.querySelector('.waitlist-form__error');
        var email = input.value.trim();

        if (!email) return;

        btn.disabled = true;
        btn.textContent = '...';
        if (error) error.hidden = true;

        var payload = { email: email };
        if (utmData.utm_source) payload.utm_source = utmData.utm_source;
        if (utmData.utm_medium) payload.utm_medium = utmData.utm_medium;
        if (utmData.utm_campaign) payload.utm_campaign = utmData.utm_campaign;

        fetch(API_URL + '/api/waitlist', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        })
            .then(function (res) {
                if (!res.ok) {
                    return res.json().then(function (data) {
                        throw new Error(data.detail || 'Erreur');
                    });
                }
                return res.json();
            })
            .then(function () {
                // Inscription OK → on dévoile l'ajout à l'agenda.
                input.value = '';
                btn.textContent = "C'est noté ✓";
                btn.disabled = true;
                revealCalendar();
            })
            .catch(function (err) {
                // Erreur réseau bénigne : on garde quand même l'ajout à l'agenda
                // (l'e-mail sera retenté plus tard), mais on signale le souci.
                if (error) {
                    error.textContent = err && err.message && err.message !== 'Erreur'
                        ? err.message
                        : 'Inscription non confirmée, mais tu peux déjà noter la date.';
                    error.hidden = false;
                }
                btn.textContent = 'Réessayer';
                btn.disabled = false;
                revealCalendar();
            });
    });
})();
