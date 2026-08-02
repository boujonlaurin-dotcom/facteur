/* Facteur Landing - Soutien à prix libre (Stripe)
 *
 * Flow : la page reçoit soit un token signé `?t=` (parcours app -> email -> web),
 * soit rien (visiteur anonyme -> on demande l'email). Au submit :
 *   POST /api/checkout/create-stripe-session { token|email, amount_cents }
 *   -> redirection vers l'URL Stripe Checkout hébergée.
 * Bornes montant alignées sur stripe_support_min_cents / _max_cents (2 / 100 EUR).
 */
(function () {
    'use strict';

    var API_URL = 'https://facteur-production.up.railway.app';
    var MIN_CENTS = 200;
    var MAX_CENTS = 10000;

    var token = new URLSearchParams(window.location.search).get('t');

    var amountBtns = Array.prototype.slice.call(document.querySelectorAll('.amt'));
    var customInput = document.getElementById('custom-amount');
    var emailRow = document.getElementById('email-row');
    var emailInput = document.getElementById('email');
    var submitBtn = document.getElementById('submit');
    var errorEl = document.getElementById('error');

    // Sans token signé, on a besoin de l'email pour relier le soutien au compte.
    if (!token && emailRow) emailRow.hidden = false;

    function showError(msg) {
        if (!errorEl) return;
        errorEl.textContent = msg;
        errorEl.hidden = false;
    }

    function clearError() {
        if (errorEl) errorEl.hidden = true;
    }

    function selectPreset(btn) {
        amountBtns.forEach(function (b) { b.classList.remove('amt--on'); });
        btn.classList.add('amt--on');
        if (customInput) customInput.value = '';
    }

    amountBtns.forEach(function (btn) {
        btn.addEventListener('click', function () {
            clearError();
            selectPreset(btn);
        });
    });

    if (customInput) {
        customInput.addEventListener('input', function () {
            clearError();
            // Une saisie custom désélectionne les presets.
            if (customInput.value) {
                amountBtns.forEach(function (b) { b.classList.remove('amt--on'); });
            }
        });
    }

    function selectedAmountCents() {
        var euros;
        if (customInput && customInput.value) {
            euros = parseFloat(customInput.value.replace(',', '.'));
        } else {
            var on = document.querySelector('.amt--on');
            euros = on ? parseFloat(on.getAttribute('data-amount')) : NaN;
        }
        if (!isFinite(euros)) return NaN;
        return Math.round(euros * 100);
    }

    // Mur des soutiens : n'affiche QUE les messages modérés (published côté API).
    // La section reste masquée s'il n'y en a aucun. Rendu via textContent -> pas
    // d'injection HTML depuis un texte utilisateur.
    function loadWall() {
        fetch(API_URL + '/api/checkout/support-messages')
            .then(function (r) { return r.ok ? r.json() : []; })
            .then(function (list) {
                if (!Array.isArray(list) || !list.length) return;
                var wall = document.getElementById('wall');
                var host = document.getElementById('wall-list');
                if (!wall || !host) return;
                list.forEach(function (m) {
                    var card = document.createElement('div');
                    card.style.cssText =
                        'background:#fff;border:1px solid #eadfce;border-radius:14px;padding:16px 18px';
                    var p = document.createElement('p');
                    p.style.cssText =
                        'margin:0;font-size:15px;line-height:1.55;color:#3a3735';
                    p.textContent = m.message;
                    card.appendChild(p);
                    if (m.display_name) {
                        var n = document.createElement('p');
                        n.style.cssText =
                            'margin:8px 0 0;font-size:13px;color:#8a847f';
                        n.textContent = m.display_name;
                        card.appendChild(n);
                    }
                    host.appendChild(card);
                });
                wall.hidden = false;
            })
            .catch(function () { /* le mur est optionnel : on ignore les erreurs */ });
    }
    loadWall();

    submitBtn.addEventListener('click', function () {
        clearError();

        var amountCents = selectedAmountCents();
        if (isNaN(amountCents)) {
            showError('Choisis ou saisis un montant.');
            return;
        }
        if (amountCents < MIN_CENTS || amountCents > MAX_CENTS) {
            showError('Le montant doit être compris entre 2 et 100 euros par mois.');
            return;
        }

        var payload = { amount_cents: amountCents };
        if (token) {
            payload.token = token;
        } else {
            var email = (emailInput && emailInput.value || '').trim();
            if (!email) {
                showError('Indique ton email pour continuer.');
                return;
            }
            payload.email = email;
        }

        var msgEl = document.getElementById('message');
        var msg = (msgEl && msgEl.value || '').trim();
        if (msg) payload.message = msg;

        var originalLabel = submitBtn.textContent;
        submitBtn.disabled = true;
        submitBtn.textContent = '...';

        fetch(API_URL + '/api/checkout/create-stripe-session', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        })
            .then(function (res) {
                if (!res.ok) {
                    return res.json().then(function (data) {
                        throw new Error((data && data.detail) || 'Erreur');
                    });
                }
                return res.json();
            })
            .then(function (data) {
                if (data && data.url) {
                    window.location.href = data.url;
                } else {
                    throw new Error('Réponse invalide');
                }
            })
            .catch(function (err) {
                var msg = 'Impossible de démarrer le paiement. Réessaie ?';
                if (err && /expired|invalid/i.test(err.message)) {
                    msg = 'Ton lien a expiré. Reviens dans l\'app et redemande un lien.';
                }
                showError(msg);
                submitBtn.textContent = originalLabel;
                submitBtn.disabled = false;
                if (window.console) console.warn('create-stripe-session failed', err);
            });
    });
})();
