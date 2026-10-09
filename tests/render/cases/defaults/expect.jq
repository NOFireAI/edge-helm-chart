(.kube | has("namespaceFilter") | not)
and (.netobs | has("edgeExistenceTtl") | not)
and (.netobs | has("excludeNamespaces") | not)
