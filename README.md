# dat-filter
Greg Kennedy <kennedy.greg@gmail.com>

## What's this?
No-intro and other sites distribute .dat files for use in RomCenter or ClrMamePro - these databases help track and organize ROM releases for different regions / revisions etc.

dat-filter is a tool to prune a .dat file to help produce a romset for users.  Given an input xml file, it will search titles for strings to remove ("proto", "beta", etc) as well as filtering out regions the user is uninterested in.

All control is user-driven via the config.txt file.

## Usage
* Edit config.txt and set options
* `./dat-filter.pl dat-file-name.dat > pruned-dat-file.dat`
* Load pruned-dat-file.dat into your ROM management tool.
