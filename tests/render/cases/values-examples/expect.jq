.kube.namespaceFilter.mode == "allow"
and .netobs.edgeExistenceTtl == "2h"
and .netobs.excludeNamespaces == ["kube-system", "monitoring"]
and .services.address == ":6000"
and .services.compression == {"enabled": true, "type": "gzip", "level": -1}
and (.services.tls.cipherSuites | length) == 4
