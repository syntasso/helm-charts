package tests_test

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

var (
	timeout     = time.Second * 100
	longTimeout = time.Second * 300
	interval    = time.Second
	context     = "--context=kind-platform"
)

var _ = Describe("ske-operator helm chart", func() {
	When("global.skeOperator.tlsConfig.certManager.disabled=false", func() {
		BeforeEach(func() {
			run("kubectl", context, "apply", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
			run("kubectl", context, "wait", "crd/certificates.cert-manager.io", "--for=condition=established", "--timeout=60s")
			Eventually(func(g Gomega) {
				runGinkgo(g, "kubectl", context, "apply", "-f", "assets/example-issuer.yaml", "--dry-run=server")
			}, timeout, interval).Should(Succeed())
			run("kubectl", context, "wait", "--for=condition=available", "deployment/cert-manager-webhook", "-n=cert-manager")
		})

		AfterEach(func() {
			cleanup()
			run("kubectl", context, "delete", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
		})

		It("can install and upgrade SKE successfully", func() {
			run("pwd")
			run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
				"-n=kratix-platform-system", "-f=./assets/values-with-certmanager.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait")

			By("creating a certificate and issuer, and use them for the webhook")
			run("kubectl", context, "get", "certificates", "ske-operator-serving-cert", "-n=kratix-platform-system")
			run("kubectl", context, "get", "issuer", "ske-operator-selfsigned-issuer", "-n=kratix-platform-system")

			By("deploying kratix")
			//if the Kratix got created successfully by helm install, this means the
			//webhook was running successfully
			run("kubectl", context, "get", "kratixes", "kratix")
			kratixVersion := r(Default, timeout, "kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.spec.version}")
			creationTimestamp := r(Default, timeout, "kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.metadata.creationTimestamp}")

			By("creating any additional resources provided in values file")
			run("kubectl", context, "get", "secrets", "git-credentials", "-n=default")
			run("kubectl", context, "get", "gitstatestores", "default")
			run("kubectl", context, "get", "destinations", "worker-1")

			By("upgrading SKE")
			run("pwd")
			run("helm", "upgrade", "ske-operator", "../ske-operator/", "-n=kratix-platform-system",
				"-f=./assets/values-with-upgrade.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait")

			Expect(r(Default, timeout, "kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.metadata.creationTimestamp}")).To(Equal(creationTimestamp))
			Expect(r(Default, timeout, "kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.spec.version}")).NotTo(Equal(kratixVersion))
		})

	})

	When("global.skeOperator.tlsConfig.certManager.disabled=true, and certs are provided", func() {
		BeforeEach(func() {
			//double check cert-manager is not installed
			crds := run("kubectl", context, "get", "crds")
			Expect(crds).NotTo(ContainSubstring("cert-manager"))
			run("./assets/generate-certs")
		})

		AfterEach(func() {
			cleanup()
		})

		It("should use the provided certs for the webhook", func() {
			run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
				"-n=kratix-platform-system", "-f=./assets/values-without-certmanager.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait",
				"--set-string", "global.skeOperator.tlsConfig.webhookTLSCert="+run("cat", "./operator-tls.crt"),
				"--set-string", "global.skeOperator.tlsConfig.webhookTLSKey="+run("cat", "./operator-tls.key"),
				"--set-string", "global.skeOperator.tlsConfig.webhookCACert="+run("cat", "./operator-ca.crt"),
				"--set-string", "skeDeployment.tlsConfig.webhookTLSCert="+run("cat", "./deployment-tls.crt"),
				"--set-string", "skeDeployment.tlsConfig.webhookTLSKey="+run("cat", "./deployment-tls.key"),
				"--set-string", "skeDeployment.tlsConfig.webhookCACert="+run("cat", "./deployment-ca.crt"))
			//if the Kratix got created successfully by helm install, this means the
			//webhook was running successfully
			run("kubectl", context, "get", "kratixes", "kratix")
			run("kubectl", context, "wait", "kratixes", "kratix", "--for=condition=KratixDeploymentReady", "--timeout=120s")
			run("kubectl", context, "apply", "-f", "assets/example-promise.yaml")
		})
	})
})

func cleanup() {
	run("kubectl", context, "delete", "kratixes", "kratix", "--timeout=60s")
	run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system", "--wait")
	runLongTimeout("kubectl", context, "delete", "namespace", "kratix-platform-system", "--timeout=300s")
}

func runLongTimeout(args ...string) string {
	return r(Default, longTimeout, args...)
}

func run(args ...string) string {
	return r(Default, timeout, args...)
}

func runGinkgo(g Gomega, args ...string) string {
	return r(g, timeout, args...)
}

func r(g Gomega, t time.Duration, args ...string) string {
	firstArg := args[0]
	remainingArgs := args[1:]
	command := exec.Command(firstArg, remainingArgs...)
	command.Env = os.Environ()
	session, err := gexec.Start(command, GinkgoWriter, GinkgoWriter)
	fmt.Fprintf(GinkgoWriter, "Running: %s %s\n", firstArg, strings.Join(remainingArgs, " "))
	g.ExpectWithOffset(2, err).ShouldNot(HaveOccurred())
	g.EventuallyWithOffset(2, session, t, interval).Should(gexec.Exit(0))
	return string(session.Out.Contents())
}
