package ske_gui_test

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

var timeout = time.Second * 100
var interval = time.Second

var _ = Describe("ske-gui helm chart", func() {
	When("an oidc config is provided", func() {
		It("templates the oidc configuration options in the deployment", func() {
			By("configuring the expected environment variables in the deployment")
			template, _ := run(
				"helm", "template", "ske-gui", "../../ske-gui/",
				"-s=templates/deployment.yaml",
				"-f=../assets/ske-gui-values-with-oidc.yaml",
				"--set-string=oidc.validatorClientID=validator-client",
				"--set-string=oidc.validatorIssuerURL=https://validator.issuer.org",
				"--set-string=oidc.usePKCE=true",
				"--set-string=oidc.meUserInfoURL=https://issuer.org/userinfo",
			)
			Expect(template).To(ContainSubstring("name: OIDC_CLIENT_SECRET\n              valueFrom:\n                secretKeyRef:\n                  name: \"headlamp-oidc-secret\"\n                  key: \"clientSecret\""))
			Expect(template).To(ContainSubstring("name: OIDC_CLIENT_ID\n              value: my-client"))
			Expect(template).To(ContainSubstring("name: OIDC_ISSUER_URL\n              value: www.issuer.org"))
			Expect(template).To(ContainSubstring("name: OIDC_SCOPES\n              value: profile,email"))
			Expect(template).To(ContainSubstring("name: OIDC_USE_ACCESS_TOKEN\n              value: \"true\""))
			Expect(template).To(ContainSubstring("name: OIDC_CALLBACK_URL\n              value: www.url.org/call/back"))
			Expect(template).To(ContainSubstring("name: OIDC_VALIDATOR_CLIENT_ID\n              value: validator-client"))
			Expect(template).To(ContainSubstring("name: OIDC_VALIDATOR_ISSUER_URL\n              value: https://validator.issuer.org"))
			Expect(template).To(ContainSubstring("name: OIDC_USE_PKCE\n              value: \"true\""))
			Expect(template).To(ContainSubstring("name: ME_USER_INFO_URL\n              value: https://issuer.org/userinfo"))

			By("configuring the expected fields in the secret")
			template, _ = run(
				"helm", "template", "ske-gui", "../../ske-gui/",
				"-s=templates/oidc-secret.yaml",
				"-f=../assets/ske-gui-values-with-oidc.yaml",
				"--set-string=oidc.validatorClientID=validator-client",
				"--set-string=oidc.validatorIssuerURL=https://validator.issuer.org",
				"--set-string=oidc.usePKCE=true",
				"--set-string=oidc.meUserInfoURL=https://issuer.org/userinfo",
			)
			Expect(template).To(ContainSubstring("clientSecret: \"dG9wLXNlY3JldA==\""))
			Expect(template).To(ContainSubstring("clientID: \"bXktY2xpZW50\""))
			Expect(template).To(ContainSubstring("validatorClientID: \"dmFsaWRhdG9yLWNsaWVudA==\""))
			Expect(template).To(ContainSubstring("validatorIssuerURL: \"aHR0cHM6Ly92YWxpZGF0b3IuaXNzdWVyLm9yZw==\""))
			Expect(template).To(ContainSubstring("usePKCE: \"dHJ1ZQ==\""))
			Expect(template).To(ContainSubstring("meUserInfoURL: \"aHR0cHM6Ly9pc3N1ZXIub3JnL3VzZXJpbmZv\""))
		})

		When("a secretRef is provided", func() {
			It("references the secretRef in the deployment and does not template a secret", func() {
				template, _ := run("helm", "template", "ske-gui", "../../ske-gui/", "-f=../assets/ske-gui-values-with-oidc.yaml", "--set-string=oidc.secretRef.name=my-secret", "--set-string=oidc.secretRef.key=clientSecret")
				Expect(template).To(ContainSubstring("name: OIDC_CLIENT_SECRET\n              valueFrom:\n                secretKeyRef:\n                  name: \"my-secret\"\n                  key: \"clientSecret\""))
				Expect(template).ToNot(ContainSubstring("# Source: ske-gui/templates/oidc-secret.yaml"))
			})
		})
	})

	When("extraArgs are specified", func() {
		It("adds the additional args to the Headlamp command in teh deployment", func() {
			template, _ := run(
				"helm", "template", "ske-gui", "../../ske-gui/",
				"-s=templates/deployment.yaml",
				"-f=../assets/ske-gui-values.yaml",
				"--set=extraArgs={--oidc-ca-file=/etc/oidc/ca.crt,--another-arg}",
			)
			Expect(template).To(ContainSubstring("--oidc-ca-file=/etc/oidc/ca.crt"))
			Expect(template).To(ContainSubstring("--another-arg"))
		})
	})

	When("additional volumes are specified", func() {
		It("templates the oidc configuration options in the deployment", func() {
			template, _ := run(
				"helm", "template", "ske-gui", "../../ske-gui/",
				"-s=templates/deployment.yaml",
				"-f=../assets/ske-gui-values.yaml",
				"--set=volumes[0].name=oidc-ca",
				"--set=volumes[0].configMap.name=headlamp-oidc-ca",
				"--set=volumes[1].name=more-config",
				"--set=volumes[1].configMap.name=headlamp-config",
			)
			Expect(template).To(ContainSubstring("headlamp-oidc-ca"))
			Expect(template).To(ContainSubstring("headlamp-config"))
		})
	})

	When("additional volumeMounts are specified", func() {
		It("templates the oidc configuration options in the deployment", func() {
			template, _ := run(
				"helm", "template", "ske-gui", "../../ske-gui/",
				"-s=templates/deployment.yaml",
				"-f=../assets/ske-gui-values.yaml",
				"--set=volumes[0].name=oidc-ca",
				"--set=volumes[0].mountPath=/etc/oidc",
				"--set=volumes[0].readOnly=true",
			)
			Expect(template).To(ContainSubstring("name: oidc-ca"))
			Expect(template).To(ContainSubstring("mountPath: /etc/oidc"))
			Expect(template).To(ContainSubstring("readOnly: true"))
		})
	})
})

func run(args ...string) (string, string) {
	return r(Default, timeout, args...)
}

func r(g Gomega, t time.Duration, args ...string) (string, string) {
	firstArg := args[0]
	remainingArgs := args[1:]
	command := exec.Command(firstArg, remainingArgs...)
	command.Env = os.Environ()
	session, err := gexec.Start(command, GinkgoWriter, GinkgoWriter)
	fmt.Fprintf(GinkgoWriter, "Running: %s %s\n", firstArg, strings.Join(remainingArgs, " "))
	g.ExpectWithOffset(2, err).ShouldNot(HaveOccurred())
	g.EventuallyWithOffset(2, session, t, interval).Should(gexec.Exit(0))
	return string(session.Out.Contents()), string(session.Err.Contents())
}
