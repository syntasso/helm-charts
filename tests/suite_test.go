package tests_test

import (
	"os"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var skeLicenseToken string
var _ = BeforeEach(func() {
	skeLicenseToken = os.Getenv("SKE_LICENSE_TOKEN")
	Expect(skeLicenseToken).NotTo(BeEmpty(), "SKE_LICENSE_TOKEN must be set")
})

func TestTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Tests Suite")
}
