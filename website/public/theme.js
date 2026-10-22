// Applies the remembered WHITE SPACE theme before first paint (loaded synchronously in <head>).
try {
  if (localStorage.getItem('kyomei-space') === 'white') document.documentElement.dataset.space = 'white';
} catch { /* storage blocked: default black space */ }
