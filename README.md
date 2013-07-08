About
=====

This is a Facter library to use omreport to gather information about a system include hardware, storage controller and front panel options.

Issues / Limitations
--------------------

1. There is a lot more this can gather.
2. It's very explicitly configured for Puppet Enterprise and the RPM installation of srvadmin.  It has no concept of alternative locations to store cached configuration or access the commandline tools.

Goals
-----

1. Provide support for multiple operating systems, and a Puppet module to install/manage OMSA on those systems.
2. Implement better caching and timeouts.
3. Support older OMSA versions, and write more future-proof code as the output of OMSA changes.  (Or, investigate the internal datastore of OMSA directly, rather than parsing command-line output.)


License
-------

I'm releasing this under the MIT license, see LICENSE.TXT for more information.
