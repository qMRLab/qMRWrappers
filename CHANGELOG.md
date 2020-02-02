# Changelog
All notable changes to the `qMRWrappers` project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2020-02-02

### Added
- ==========================================
- mt_sat_wrapper.m: Wrapper for MTsat fitting. 
    - Accepts BIDS and custom conventions. 
    - Timing parameters in json files are in milliseconds.
    - TR is named as RepetitionTime NOT RepetitionTimeExcitation 
- ===========================================
- filter_map_wrapper.m: Wrapper for filtering B1 maps.
- ===========================================
- init_qmrlab_wrapper.sh 
    - To checkout a specific version or the latest version of this repo.
    - Example: `sh init_qmrlab_wrapper v1.0.0`
- ===========================================
- version.txt
    - Keep record of the latest tag. 

### Changed
- Nothing changed.

### Removed
- Nothing removed.