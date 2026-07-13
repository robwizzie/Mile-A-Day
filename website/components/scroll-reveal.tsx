"use client";

import { useEffect } from "react";

const REVEAL_SELECTOR = ".reveal, .reveal-left, .reveal-right, .reveal-scale";

export function ScrollReveal() {
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
          }
        });
      },
      { threshold: 0.1, rootMargin: "0px 0px -40px 0px" },
    );

    const observeWithin = (root: ParentNode) => {
      root
        .querySelectorAll(REVEAL_SELECTOR)
        .forEach((el) => observer.observe(el));
    };

    observeWithin(document);

    // Components driven by live data (community count, stats band) mount their
    // reveal elements AFTER this initial scan — without re-observing them they
    // stay at the reveal classes' opacity:0 forever. Watch the DOM for
    // late-mounted reveal elements and observe those too.
    const mutations = new MutationObserver((records) => {
      for (const record of records) {
        record.addedNodes.forEach((node) => {
          if (!(node instanceof Element)) return;
          if (node.matches(REVEAL_SELECTOR)) observer.observe(node);
          observeWithin(node);
        });
      }
    });
    mutations.observe(document.body, { childList: true, subtree: true });

    return () => {
      observer.disconnect();
      mutations.disconnect();
    };
  }, []);

  return null;
}
