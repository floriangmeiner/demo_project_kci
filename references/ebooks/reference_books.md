# Reference Books

Books used for this project, cited in IEEE style. The PDFs are kept locally
and aren't committed: `.gitignore` excludes `references/ebooks/*.pdf`.

[1] J. Yiu, *The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors*,
3rd ed. Oxford, U.K.: Newnes, 2014.

- **Local copy:** [The Definitive Guide to ARM Cortex-M3 and Cortex-M4
  Processors 3ed.pdf](<The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors 3ed.pdf>)
- **ISBN:** 978-0-12-408082-9
- **Relevance:** the STM32F746 has a Cortex-M7, which uses the same ARMv7-M
  architecture as the M3 and M4. The book's chapters on the exception model,
  fault handling, the MPU and the fault status registers apply here. It
  doesn't cover features new in the M7, such as the caches, the TCM memories
  and the AXI bus.
