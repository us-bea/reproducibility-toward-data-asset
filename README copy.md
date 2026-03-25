# Toward Experimental Economic Statistics on Own Account Data and Databases

Reproducibility artifact for the [BEA Working Paper: Toward Experimental Economic Statistics on Own Account Data and Databases](https://bea.gov/index.php/research/papers/2026/toward-economics-statistics-own-account-data-and-databases-assets-1997-2024).

## Setup
- Use the `.devcontainer` files to compose the container.
- Run the scripts in order:
  - `_klems.qmd`
  - `00_oews.qmd`
  - `01_gfcf.qmd`
  - `02_volume.qmd`
  - `03_netstock.qmd`
  - `04_impact.qmd`
  - `05_tables.qmd`

## Summary

- Certain data files that cannot be programatically downloaded due to website restrictions have been included for convenience.
- Large data files that are processed within the files only attempt to run the code to generate these if the cache versions are not available. These parsed and processed files have been provided to make the code more accessible.
