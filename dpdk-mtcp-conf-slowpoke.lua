-- Configuration for all DPDK command line parameters.
-- See DPDK documentation at http://dpdk.org/doc/guides/testpmd_app_ug/run_app.html for details.
-- libmoon tries to choose reasonable defaults, so this config file can almost always be empty.
-- Be careful when running libmoon in a VM that also uses another virtio NIC, e.g., for internet access.
-- In this case it may be necessary to use the blacklist or whitelist features in some configurations.
DPDKConfig {
	-- configure the CPU cores to use, default: all cores
	--cores = {0, 10, 11, 12, 13, 14, 15},
	
	-- max number of shared tasks running on core 0
	--sharedCores = 8,

	-- black or whitelist devices to limit which PCI devs are used by DPDK
	-- only one of the following examples can be used
	--pciBlacklist = {"0000:81:00.3","0000:81:00.1"},
	--pciWhitelist = {"0000:81:00.3","0000:81:00.1"},
	
	-- arbitrary DPDK command line options
	-- the following configuration allows multiple DPDK instances (use together with pciWhitelist)
	-- cf. http://dpdk.org/doc/guides/prog_guide/multi_proc_support.html#running-multiple-independent-dpdk-applications
	--cli = {
	--	"--file-prefix", "m1",
	--	"--socket-mem", "512,512",
	--}
	pciWhitelist = {"0000:03:00.0", "0000:02:00.0", "0000:01:00.0"},
	coreMapping = "0-3,(4,5)@1,(6,7)@2"
}

-- argv: {"libmoon", "-c0x000000000000000F", "--lcores=0-3,(4,5)@1,(6,7)@2,(8,9)@2,(10,11)@3", "--file-prefix", "m2", "--socket-mem", "512"}