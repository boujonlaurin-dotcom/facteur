// Page /methodologie — scroll FX (accordéon des critères) + formulaire comité.
// Port vanilla du composant design-canvas « Méthodologie facteur.app v4 ».
(function () {
    'use strict';

    var API_URL = 'https://facteur-production.up.railway.app';

    // ─── Scroll FX ───────────────────────────────────────────────────────
    // Désactivé sur écrans tactiles (mobile/tablette) : la fenêtre de focus
    // scroll-lié y est trop étroite et le collapse de l'accordéon provoque un
    // saut de page. Filet de sécurité déjà présent dans le CSS : sans
    // data-scrollfx, les critères s'affichent statiquement, tous dépliés.
    var wantsScrollFx = !window.matchMedia('(prefers-reduced-motion: reduce)').matches
        && window.matchMedia('(pointer: fine)').matches;
    if (wantsScrollFx) {
        document.documentElement.setAttribute('data-scrollfx', '1');

        var pinned = null;
        var pinTimer = null;
        var crits = Array.prototype.slice.call(document.querySelectorAll('[data-crit]'));
        var steps = Array.prototype.slice.call(document.querySelectorAll('[data-step]'));
        var axes = Array.prototype.slice.call(document.querySelectorAll('[data-axis]'));

        var tick = function () {
            var vh = window.innerHeight;
            crits.forEach(function (el) {
                var r = el.getBoundingClientRect();
                if (!el.hasAttribute('data-in') && r.top < vh * 0.95 && r.bottom > 0) {
                    el.setAttribute('data-in', '1');
                }
            });
            // Un seul critère « focus » : celui dont l'en-tête est le plus
            // proche de la ligne focale (42 % de la hauteur du viewport).
            var best = null;
            var bestDist = Infinity;
            var focal = vh * 0.42;
            crits.forEach(function (el) {
                if (!el.hasAttribute('data-in')) return;
                var r = el.getBoundingClientRect();
                var headMid = r.top + Math.min(r.height, 130) / 2;
                var d = Math.abs(headMid - focal);
                if (d < bestDist && headMid > -vh * 0.2 && headMid < vh * 1.1) {
                    bestDist = d;
                    best = el;
                }
            });
            var winner = pinned || (bestDist < vh * 0.55 ? best : null);
            crits.forEach(function (el) {
                if (el === winner) el.setAttribute('data-focus', '1');
                else el.removeAttribute('data-focus');
            });
            // Étapes du processus : même règle de focus unique.
            var bStep = null;
            var bD = Infinity;
            steps.forEach(function (el) {
                var r = el.getBoundingClientRect();
                if (!el.hasAttribute('data-in') && r.top < vh * 0.92 && r.bottom > 0) {
                    el.setAttribute('data-in', '1');
                }
                var mid = r.top + Math.min(r.height, 120) / 2;
                var d = Math.abs(mid - vh * 0.45);
                if (d < bD) {
                    bD = d;
                    bStep = el;
                }
            });
            steps.forEach(function (el) {
                if (el === bStep && el.hasAttribute('data-in') && bD < vh * 0.5) {
                    el.setAttribute('data-focus', '1');
                } else {
                    el.removeAttribute('data-focus');
                }
            });
            axes.forEach(function (el) {
                var r = el.getBoundingClientRect();
                if (r.top < vh * 0.85 && r.bottom > vh * 0.05) el.setAttribute('data-active', '1');
                else el.removeAttribute('data-active');
            });
        };

        // Au plus un tick par frame quand le scroll spamme les events.
        var rafPending = false;
        var scheduleTick = function () {
            if (rafPending) return;
            rafPending = true;
            requestAnimationFrame(function () {
                rafPending = false;
                tick();
            });
        };
        window.addEventListener('scroll', scheduleTick, { passive: true });
        window.addEventListener('resize', scheduleTick, { passive: true });
        setInterval(scheduleTick, 150);
        tick();

        // Clic sur un critère : le « pin » en focus pendant 2,5 s.
        document.addEventListener('click', function (ev) {
            var el = ev.target.closest && ev.target.closest('[data-crit]');
            if (!el) return;
            pinned = el;
            el.setAttribute('data-in', '1');
            clearTimeout(pinTimer);
            pinTimer = setTimeout(function () {
                pinned = null;
                tick();
            }, 2500);
            tick();
        });
    }

    // ─── Formulaire « Rejoindre le comité de revue » ─────────────────────
    var form = document.getElementById('comite-form');
    if (!form) return;
    var success = document.getElementById('comite-success');
    var errorBox = document.getElementById('comite-error');
    var submitBtn = document.getElementById('comite-submit');

    var showError = function (msg) {
        errorBox.textContent = msg;
        errorBox.hidden = false;
    };

    form.addEventListener('submit', function (e) {
        e.preventDefault();
        var email = (document.getElementById('comite-email').value || '').trim();
        if (!/^\S+@\S+\.\S+$/.test(email)) {
            showError("Merci d'indiquer une adresse email valide.");
            return;
        }
        errorBox.hidden = true;
        submitBtn.disabled = true;

        var motivation = (document.getElementById('comite-motivation').value || '').trim();
        var payload = {
            email: email,
            utm_source: 'site',
            utm_medium: 'methodologie',
            utm_campaign: 'methodologie-comite',
            methode_complete: !!document.getElementById('comite-methode').checked
        };
        if (motivation) payload.motivation = motivation;

        fetch(API_URL + '/api/waitlist', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        })
            .then(function (res) {
                if (res.ok) {
                    form.hidden = true;
                    success.hidden = false;
                } else {
                    showError("L'envoi n'a pas abouti. Réessayez dans un instant.");
                }
            })
            .catch(function () {
                showError("L'envoi n'a pas abouti. Vérifiez votre connexion et réessayez.");
            })
            .then(function () {
                submitBtn.disabled = false;
            });
    });
})();
