package tests_test

import (
	"encoding/base64"
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
	interval = time.Second

	timeout     = time.Second * 100
	longTimeout = time.Second * 300

	kubectlTimeout       = time.Second * 60
	kubectlMediumTimeout = time.Second * 120
	kubectlLongTimeout   = time.Second * 300

	context = "--context=kind-platform"
)

var _ = Describe("ske-operator helm chart", func() {
	When("global.skeOperator.tlsConfig.certManager.disabled=false", func() {
		var kratixVersion, upgradedKratixVersion, creationTimestamp, gitStateStoreCreationTimestamp, destinationCreationTimestamp string
		BeforeEach(func() {
			run("kubectl", context, "apply", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
			run("kubectl", context, "wait", "crd/certificates.cert-manager.io", "--for=condition=established", "--timeout="+formatTimeout(kubectlTimeout))
			validateCertManagerWebhook()
			run("kubectl", context, "wait", "--for=condition=available", "deployment/cert-manager-webhook", "-n=cert-manager")
		})

		AfterEach(func() {
			runLongTimeout("kubectl", context, "delete", "namespace", "kratix-platform-system", "--timeout="+formatTimeout(kubectlLongTimeout), "--ignore-not-found")
			run("kubectl", context, "delete", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
			deleteCRDs(context)
		})

		It("can install, upgrade and uninstall SKE successfully", func() {
			By("installing SKE", func() {
				run("pwd")
				run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
					"-n=kratix-platform-system", "-f=./assets/values-with-certmanager.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait")

				By("creating a certificate and issuer, and use them for the webhook")
				run("kubectl", context, "get", "certificates", "ske-operator-serving-cert", "-n=kratix-platform-system")
				run("kubectl", context, "get", "issuer", "ske-operator-selfsigned-issuer", "-n=kratix-platform-system")

				By("deploying kratix", func() {
					// if the Kratix got created successfully by helm install, this means the
					// webhook was running successfully
					run("kubectl", context, "get", "kratixes", "kratix")
					kratixVersion = run("kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.spec.version}")
					creationTimestamp = run("kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.metadata.creationTimestamp}")
				})

				By("creating any additional resources provided in values file", func() {
					run("kubectl", context, "get", "secrets", "git-credentials", "-n=default")
					run("kubectl", context, "get", "configmaps", "test-cm", "-n=default")
					run("kubectl", context, "get", "gitstatestores", "default")
					gitStateStoreCreationTimestamp = run("kubectl", context, "get", "gitstatestores", "default", "-o", "jsonpath={.metadata.creationTimestamp}")
					run("kubectl", context, "get", "destinations", "worker-1")
					destinationCreationTimestamp = run("kubectl", context, "get", "destinations", "worker-1", "-o", "jsonpath={.metadata.creationTimestamp}")
				})
			})

			By("upgrading SKE", func() {
				run("pwd")
				run("helm", "upgrade", "ske-operator", "../ske-operator/", "-n=kratix-platform-system",
					"-f=./assets/values-with-upgrade.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait")

				By("upgrading SKE version", func() {
					Expect(run("kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.metadata.creationTimestamp}")).To(Equal(creationTimestamp))
					upgradedKratixVersion = run("kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.spec.version}")
					Expect(upgradedKratixVersion).NotTo(Equal(kratixVersion))
				})

				By("updating some additional resources", func() {
					encodedUsername := run("kubectl", context, "get", "secrets", "git-credentials", "-o", "jsonpath={.data.username}")
					decodedUsername, err := base64.StdEncoding.DecodeString(encodedUsername)
					Expect(err).NotTo(HaveOccurred())
					Expect(string(decodedUsername)).To(Equal("now"))
				})

				By("deleting some additional resources", func() {
					Expect(run("kubectl", context, "get", "configmaps", "default", "--ignore-not-found")).To(BeEmpty())
				})

				By("updating some SKE additional resources", func() {
					Expect(run("kubectl", context, "get", "gitstatestores.platform.kratix.io", "default", "-o", "jsonpath={.metadata.creationTimestamp}")).To(Equal(gitStateStoreCreationTimestamp))
					Expect(run("kubectl", context, "get", "destinations.platform.kratix.io", "worker-1", "-o", "jsonpath={.metadata.labels.environment}")).To(Equal("prod"))
					Expect(run("kubectl", context, "get", "destinations.platform.kratix.io", "worker-1", "-o", "jsonpath={.metadata.creationTimestamp}")).To(Equal(destinationCreationTimestamp))
				})
			})

			By("uninstalling SKE", func() {
				run("pwd")
				run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system", "--wait")

				By("deleting operator", func() {
					Expect(run("kubectl", context, "get", "deployments", "ske-operator-controller-manager", "--ignore-not-found")).To(BeEmpty())
				})

				By("retaining the Kratix deployment", func() {
					Expect(run("kubectl", context, "get", "deployments", "kratix-platform-controller-manager", "-n=kratix-platform-system")).ToNot(BeEmpty())
				})

				By("retaining the Kratix CR", func() {
					Expect(run("kubectl", context, "get", "kratixes", "kratix", "-o", "jsonpath={.spec.version}")).To(Equal(upgradedKratixVersion))
				})

				By("retaining the crds", func() {
					Expect(run("kubectl", context, "get", "crds")).To(ContainSubstring("kratixes.platform.syntasso.io"))
				})

				By("retaining the registry secret", func() {
					Expect(run("kubectl", context, "get", "secret", "-n=kratix-platform-system")).To(ContainSubstring("syntasso-registry"))
				})

				By("deleting the additional resources", func() {
					Expect(run("kubectl", context, "get", "secrets", "git-credentials", "--ignore-not-found")).To(BeEmpty())
					Expect(run("kubectl", context, "get", "configmaps", "default", "--ignore-not-found")).To(BeEmpty())
				})
			})
		})
	})

	FWhen("global.skeOperator.tlsConfig.certManager.disabled=true, and certs are provided", func() {
		BeforeEach(func() {
			// double check cert-manager is not installed
			crds := run("kubectl", context, "get", "crds")
			Expect(crds).NotTo(ContainSubstring("cert-manager"))
			run("./assets/generate-certs")
			run("./assets/generate-metrics-certs")
		})

		AfterEach(func() {
			run("kubectl", context, "delete", "kratixes", "kratix", "--timeout="+formatTimeout(kubectlTimeout))
			run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system", "--wait")
			runLongTimeout("kubectl", context, "delete", "namespace", "kratix-platform-system", "--timeout="+formatTimeout(kubectlLongTimeout))
			deleteCRDs(context)
		})

		It("should use the provided certs for the webhook", func() {
			By("installing the operator with helm and the provided certs", func() {
				run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
					"-n=kratix-platform-system", "-f=./assets/values-without-certmanager.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait",
					"--set-string", "global.skeOperator.tlsConfig.webhookTLSCert="+run("cat", "./operator-tls.crt"),
					"--set-string", "global.skeOperator.tlsConfig.webhookTLSKey="+run("cat", "./operator-tls.key"),
					"--set-string", "global.skeOperator.tlsConfig.webhookCACert="+run("cat", "./operator-ca.crt"),
					"--set-string", "skeDeployment.tlsConfig.webhookTLSCert="+run("cat", "./deployment-tls.crt"),
					"--set-string", "skeDeployment.tlsConfig.webhookTLSKey="+run("cat", "./deployment-tls.key"),
					"--set-string", "skeDeployment.tlsConfig.webhookCACert="+run("cat", "./deployment-ca.crt"),
					"--set-string", "skeDeployment.tlsConfig.metricsServerTLSCert="+run("cat", "./metrics-tls.crt"),
					"--set-string", "skeDeployment.tlsConfig.metricsServerTLSKey="+run("cat", "./metrics-tls.key"),
					"--set-string", "skeDeployment.tlsConfig.metricsServerCACert="+run("cat", "./metrics-ca.crt"))
			})

			By("verifying that Kratix got created successfully by helm install", func() {
				run("kubectl", context, "get", "kratixes", "kratix")
				run("kubectl", context, "wait", "kratixes", "kratix", "--for=condition=KratixDeploymentReady", "--timeout="+formatTimeout(kubectlMediumTimeout))
			})

			By("installing a promise to validate that Kratix is running fine", func() {
				run("kubectl", context, "apply", "-f", "assets/example-promise.yaml", "--timeout="+formatTimeout(kubectlTimeout))
				run("kubectl", context, "wait", "promises", "namespace-delta", "--for=condition=Available", "--timeout="+formatTimeout(kubectlTimeout))
			})

			By("removing the promise to clean up resources", func() {
				run("kubectl", context, "delete", "promises", "--all", "--timeout="+formatTimeout(kubectlMediumTimeout))
			})
		})
	})

	Describe("deleteOnUninstall", func() {
		When("deleteOnUninstall is not set", func() {
			It("the secret template sets the resource-policy to 'keep'", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=templates/registry-secret.yaml", "-f=./assets/values-with-certmanager.yaml")
				Expect(template).To(ContainSubstring("helm.sh/resource-policy: keep"))
			})

			It("the CRD template sets the resource-policy to 'keep'", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=charts/ske-operator-crds/templates/crds-with-cert-manager.yaml", "-f=./assets/values-with-certmanager.yaml")
				Expect(template).To(ContainSubstring("helm.sh/resource-policy: keep"))
			})
		})

		When("deleteOnUninstall is set to false", func() {
			It("the secret template sets the resource-policy to 'keep'", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=templates/registry-secret.yaml", "-f=./assets/values-with-delete-on-uninstall-false.yaml")
				Expect(template).To(ContainSubstring("helm.sh/resource-policy: keep"))
			})

			It("the CRD template sets the resource-policy to 'keep'", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=charts/ske-operator-crds/templates/crds-with-cert-manager.yaml", "-f=./assets/values-with-delete-on-uninstall-false.yaml")
				Expect(template).To(ContainSubstring("helm.sh/resource-policy: keep"))
			})
		})

		When("deleteOnUninstall is set to true", func() {
			BeforeEach(func() {
				run("kubectl", context, "apply", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
				run("kubectl", context, "wait", "crd/certificates.cert-manager.io", "--for=condition=established", "--timeout="+fmt.Sprintf("%ds", int(kubectlTimeout.Seconds())))
				validateCertManagerWebhook()
				run("kubectl", context, "wait", "--for=condition=available", "deployment/cert-manager-webhook", "-n=cert-manager")
			})

			AfterEach(func() {
				runLongTimeout("kubectl", context, "delete", "namespace", "kratix-platform-system", "--timeout="+formatTimeout(kubectlLongTimeout), "--ignore-not-found")
				run("kubectl", context, "delete", "-f=https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml")
				deleteCRDs(context)
			})

			It("uninstalls the deployed kratix when uninstalling the ske operator", func() {
				By("setting the secret template resource-policy to 'keep'", func() {
					template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=templates/registry-secret.yaml", "-f=./assets/values-with-delete-on-uninstall-true.yaml")
					Expect(template).ToNot(ContainSubstring("helm.sh/resource-policy: keep"))
				})

				By("setting the crd template resource-policy to 'keep'", func() {
					template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=charts/ske-operator-crds/templates/crds-with-cert-manager.yaml", "-f=./assets/values-with-delete-on-uninstall-true.yaml")
					Expect(template).ToNot(ContainSubstring("helm.sh/resource-policy: keep"))
				})

				By("installing the ske operator", func() {
					run("pwd")
					run("helm", "install", "ske-operator", "--create-namespace", "../ske-operator/",
						"-n=kratix-platform-system", "-f=./assets/values-with-delete-on-uninstall-true.yaml", "--set-string", "skeLicense="+skeLicenseToken, "--wait")

					run("kubectl", context, "get", "kratixes", "kratix")
					run("kubectl", context, "wait", "kratixes", "kratix", "--for=condition=KratixDeploymentReady", "--timeout="+fmt.Sprintf("%ds", int(kubectlMediumTimeout.Seconds())))
				})

				By("uninstalling the ske operator", func() {
					run("pwd")
					run("helm", "uninstall", "ske-operator", "-n=kratix-platform-system", "--wait")

					By("deleting operator", func() {
						Expect(run("kubectl", context, "get", "deployments", "ske-operator-controller-manager", "--ignore-not-found")).To(BeEmpty())
					})

					By("deleting the Kratix deployment", func() {
						Expect(run("kubectl", context, "get", "deployments", "kratix-platform-controller-manager", "-n=kratix-platform-system", "--ignore-not-found")).To(BeEmpty())
					})

					By("deleting the crds", func() { // if the crds are deleted, so are the Kratix custom resources
						Expect(run("kubectl", context, "get", "crds")).ToNot(ContainSubstring("kratixes.platform.syntasso.io"))
					})

					By("deleting the registry secret", func() {
						Expect(run("kubectl", context, "get", "secret", "-n=kratix-platform-system")).ToNot(ContainSubstring("syntasso-registry"))
					})
				})
			})
		})
	})

	When("user provides a custom cert-manager issuer", func() {
		It("templates use the custom issuer", func() {
			By("setting the custom issuer on certificates and not having the self-signed issuer", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=templates/with-cert-manager.yaml", "-f=./assets/values-with-certmanager-custom-issuer.yaml")
				Expect(template).To(MatchRegexp(`issuerRef:\s+kind:\s+ClusterIssuer\s+name:\s+custom-issuer`))
				Expect(template).NotTo(MatchRegexp(`apiVersion:\s+cert-manager.io/v1\s+kind:\s+Issuer\s+`))
			})

			By("setting the custom issuer on ske-deployment config", func() {
				template := run("helm", "template", "ske-operator", "../ske-operator/", "-s=templates/ske-deployment-config.yaml", "-f=./assets/values-with-certmanager-custom-issuer.yaml")
				Expect(template).To(MatchRegexp(`issuerRef:\s+kind:\s+ClusterIssuer\s+name:\s+custom-issuer`))
			})
		})
	})
})

func validateCertManagerWebhook() {
	// It takes a while for the webhook to be ready, so we need to retry this with a timeout
	Eventually(func(g Gomega) {
		runGinkgo(g, "kubectl", context, "apply", "-f", "assets/example-issuer.yaml", "--dry-run=server")
	}, timeout, interval).Should(Succeed())
}

func formatTimeout(timeout time.Duration) string {
	return fmt.Sprintf("%ds", int(timeout.Seconds()))
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

func deleteCRDs(context string) {
	run("kubectl", context, "delete", "crd", "bucketstatestores.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "destinations.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "gitstatestores.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "healthrecords.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "kratixes.platform.syntasso.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "promisereleases.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "promises.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "workplacements.platform.kratix.io", "--ignore-not-found")
	run("kubectl", context, "delete", "crd", "works.platform.kratix.io", "--ignore-not-found")
}
