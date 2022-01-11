manifest_entitle:
	@if [ "${ENTITLEMENT_PEM}" ]; then \
	  make _manifest_entitle; \
	else \
	  echo "ENTITLEMENT_PEM not defined, not preparing the entitlement manifests."; \
	fi
_manifest_entitle:
	@echo "PEM:      ${ENTITLEMENT_PEM}"
	@[ -f "${ENTITLEMENT_PEM}" ]
	@echo "RHSM:     ${ENTITLEMENT_RHSM}"
	@[ -f "${ENTITLEMENT_RHSM}" ]
	@echo "Template: ${ENTITLEMENT_TEMPLATE}"
	@[ -f "${ENTITLEMENT_TEMPLATE}" ]
	@echo "Dest:     ${ENTITLEMENT_DST_BASENAME}*"
	@cat "${ENTITLEMENT_TEMPLATE}" \
	  | sed "s/BASE64_ENCODED_PEM_FILE/$(shell base64 -w 0 ${ENTITLEMENT_PEM})/g" \
	  | sed "s/BASE64_ENCODED_RHSM_FILE/$(shell base64 -w 0 ${ENTITLEMENT_RHSM})/g" \
	  > "${ENTITLEMENT_DST_BASENAME}.yaml"
	@# Split "${ENTITLEMENT_DST_BASENAME}.yaml" into multiple files containing a single YAML object
	@# openshift-install doesn't allow files with multiple objects
	@awk '{ print > "${ENTITLEMENT_DST_BASENAME}_"++i".yaml" }' RS='---\n' "${ENTITLEMENT_DST_BASENAME}.yaml"
	@rm "${ENTITLEMENT_DST_BASENAME}.yaml"
	@echo "Entitlement MachineConfig generated:"
	@ls "${ENTITLEMENT_DST_BASENAME}"_*
