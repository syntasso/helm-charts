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
	timeout  = time.Second * 20
	interval = time.Second
)

var _ = Describe("ske-operator helm chart", func() {
	FContext("when global.enableCertManager=true", func() {
		BeforeEach(func() {
			run("kubectl", "apply", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
			run("kubectl", "wait", "crd/certificates.cert-manager.io", "--for=condition=established", "--timeout=60s")
			run("kubectl", "wait", "--for=condition=available", "deployment/cert-manager-webhook", "-n=cert-manager")
		})

		AfterEach(func() {
			run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system")
			run("kubectl", "delete", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
		})

		It("should create a certificate and issuer, and use them for the webhook", func() {
			run("pwd")
			run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
				"-n=kratix-platform-system", "-f=./assets/values-with-certmanager.yaml", "--set-string skeLicense="+skeLicenseToken, "--wait")

			run("kubectl", "get", "certificates", "ske-operator-webhook-cert", "-n=kratix-platform-system")
			run("kubectl", "get", "issuer", "ske-operator-webhook-cert", "-n=kratix-platform-system")

			//if the Kratix got created successfully by helm install, this means the
			//webhook was running successfully
			run("kubectl", "get", "kratix", "kratix")
		})
	})

	Context("when global.enableCertManager=false, and certs are provided", func() {
		BeforeEach(func() {
			//double check cert-manager is not installed
			crds := run("kubectl", "get", "crds")
			Expect(crds).NotTo(ContainSubstring("cert-manager"))
		})

		AfterEach(func() {
			run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system")
		})

		It("should create use the provided certs for the webhook", func() {
			run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
				"-n=kratix-platform-system", "-f=./assets/values-without-certmanager.yaml", "--set-string skeLicense="+skeLicenseToken, "--wait")

			//if the Kratix got created successfully by helm install, this means the
			//webhook was running successfully
			run("kubectl", "get", "kratix", "kratix")
		})
	})
})

func run(args ...string) string {
	firstArg := args[0]
	remainingArgs := args[1:]
	command := exec.Command(firstArg, remainingArgs...)
	command.Env = os.Environ()
	session, err := gexec.Start(command, GinkgoWriter, GinkgoWriter)
	fmt.Fprintf(GinkgoWriter, "Running: %s %s\n", firstArg, strings.Join(remainingArgs, " "))
	ExpectWithOffset(1, err).ShouldNot(HaveOccurred())
	EventuallyWithOffset(1, session, timeout, interval).Should(gexec.Exit(0))
	return string(session.Out.Contents())
}
