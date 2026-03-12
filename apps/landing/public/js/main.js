/* Facteur Landing Page */

(function () {
    'use strict';

    // TODO: update with production API URL or custom domain
    var API_URL = 'https://facteur-production.up.railway.app';

    // ── Scroll Reveal ─────────────────────────────
    var observer = new IntersectionObserver(
        function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.classList.add('visible');
                }
            });
        },
        { threshold: 0.15 }
    );

    document.querySelectorAll('.reveal').forEach(function (el) {
        observer.observe(el);
    });

    // ── Waitlist Forms ────────────────────────────
    document.querySelectorAll('.waitlist-form').forEach(function (form) {
        form.addEventListener('submit', function (e) {
            e.preventDefault();

            var input = form.querySelector('.waitlist-form__input');
            var btn = form.querySelector('.waitlist-form__btn');
            var success = form.querySelector('.waitlist-form__success');
            var error = form.querySelector('.waitlist-form__error');
            var email = input.value.trim();

            if (!email) return;

            btn.disabled = true;
            btn.textContent = '...';
            error.hidden = true;

            fetch(API_URL + '/api/waitlist', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email: email }),
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
                    success.hidden = false;
                    input.value = '';
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = true;
                })
                .catch(function (err) {
                    error.textContent = err.message === 'Erreur'
                        ? 'Une erreur est survenue. Réessaie.'
                        : err.message;
                    error.hidden = false;
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = false;
                });
        });
    });

    // ── Smooth scroll for anchor links ────────────
    document.querySelectorAll('a[href^="#"]').forEach(function (link) {
        link.addEventListener('click', function (e) {
            var target = document.querySelector(link.getAttribute('href'));
            if (target) {
                e.preventDefault();
                target.scrollIntoView({ behavior: 'smooth' });
            }
        });
    });
})();
