package ske_gui_test

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestSkeGui(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "SkeGui Suite")
}
