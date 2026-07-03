// assets/main.js

document.addEventListener('DOMContentLoaded', () => {
    initCounter();
    initLightbox();
});

// --- PHP Visitor Counter ---
function initCounter() {
    // Only fetch if we have an element to display it in (e.g. on the home page)
    // Or we fetch purely to increment. The requirement says "Every page load should increment".
    // So we fetch regardless, but only update UI if the element exists.
    
    fetch('counter.php')
        .then(response => {
            if (!response.ok) throw new Error('Network response was not ok');
            return response.json();
        })
        .then(data => {
            const count = data.count;
            console.log('Visitor count:', count);
            
            // Format: "this site has been clicked NN times since 1/1/2020"
            const footerEl = document.getElementById('footer-counter');
            if (footerEl) {
                // Ensure text is lowercase as requested
                footerEl.textContent = `this site has been clicked ${count} times since 1/1/2020`;
            }
        })
        .catch(error => {
            console.error('Error fetching counter:', error);
            // Fallback or silent fail
        });
}

// --- Lightbox for Gallery ---
function initLightbox() {
    const galleryItems = document.querySelectorAll('.gallery-item');
    if (galleryItems.length === 0) return;

    // Create lightbox DOM if not exists
    let lightbox = document.getElementById('lightbox');
    if (!lightbox) {
        lightbox = document.createElement('div');
        lightbox.id = 'lightbox';
        lightbox.className = 'lightbox';
        lightbox.innerHTML = '<img src="" alt="Full size preview">';
        document.body.appendChild(lightbox);
        
        // Close on click
        lightbox.addEventListener('click', () => {
            lightbox.classList.remove('active');
            setTimeout(() => {
                lightbox.style.display = 'none';
            }, 300);
        });
    }

    const lightboxImg = lightbox.querySelector('img');

    galleryItems.forEach(item => {
        item.addEventListener('click', (e) => {
            const img = item.querySelector('img');
            const src = img.getAttribute('src'); // In a real app, maybe use a data-full-src attribute
            
            lightboxImg.src = src;
            lightbox.style.display = 'flex';
            // Slight delay to allow display:flex to apply before adding class for opacity transition
            requestAnimationFrame(() => {
                lightbox.classList.add('active');
            });
        });
    });
}
