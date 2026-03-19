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
			template, _ := run("helm", "template", "ske-gui", "../../ske-gui/", "-f=../assets/ske-gui-values-with-oidc.yaml")
			Expect(template).To(ContainSubstring("name: OIDC_CLIENT_SECRET\n              value: top-secret"))
			Expect(template).To(ContainSubstring("name: OIDC_CLIENT_ID\n              value: my-client"))

			By("configuring the expected fields in the secret")
			template, _ = run("helm", "template", "ske-gui", "../../ske-gui/", "-s=templates/oidc-secret.yaml", "-f=../assets/ske-gui-values-with-oidc.yaml")
			Expect(template).To(ContainSubstring("client-secret: \"dG9wLXNlY3JldA==\""))
			Expect(template).To(ContainSubstring("clientID: \"bXktY2xpZW50\""))
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
