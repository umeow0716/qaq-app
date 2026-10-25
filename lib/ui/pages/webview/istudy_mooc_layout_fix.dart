bool isIStudyMoocPhpUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  return uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'istudy.ntut.edu.tw' &&
      (uri.path.startsWith('/mooc/') || uri.path.startsWith('/forum/') || uri.path.startsWith('/info/'));
}

const iStudyMoocLayoutFixScript = r'''
(() => {
  const isTargetPage = () =>
    window.location.protocol === 'https:' &&
    window.location.hostname.toLowerCase() === 'istudy.ntut.edu.tw' &&
    (window.location.pathname.startsWith('/mooc/') || window.location.pathname.startsWith('/forum/') || window.location.pathname.startsWith('/info/'));

  if (!isTargetPage()) return;

  const setAuto = (element, property) => {
    if (!element) return;
    if (
      element.style.getPropertyValue(property) === 'auto' &&
      element.style.getPropertyPriority(property) === 'important'
    ) {
      return;
    }
    element.style.setProperty(property, 'auto', 'important');
  };

  const applyFix = () => {
    if (!isTargetPage()) return;
    setAuto(document.querySelector('nav'), 'height');
    setAuto(document.querySelector('#search_box_pc'), 'width');
  };

  const observerKey = '__qaqIStudyMoocLayoutFixObserver';
  const oldObserver = window[observerKey];
  if (oldObserver && typeof oldObserver.disconnect === 'function') {
    oldObserver.disconnect();
  }

  applyFix();

  if (!document.documentElement) return;
  const observer = new MutationObserver(applyFix);
  observer.observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['style'],
  });
  window[observerKey] = observer;
})();
''';
