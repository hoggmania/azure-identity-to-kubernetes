/*
Copyright Sparebanken Vest

Based on the Kubernetes controller example at
https://github.com/kubernetes/sample-controller

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"flag"
	"os"

	log "github.com/sirupsen/logrus"

	"k8s.io/client-go/kubernetes"
	typedcorev1 "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/record"

	"github.com/SparebankenVest/azure-key-vault-to-kubernetes/pkg/akv2k8s"
	"github.com/SparebankenVest/azure-key-vault-to-kubernetes/pkg/azure/credentialprovider"
)

var (
	masterURL   string
	kubeconfig  string
	cloudconfig string
	logLevel    string
	version     string
)

const controllerAgentName = "azureidentitycontroller"

func main() {
	flag.Parse()
	akv2k8s.Version = version

	logFormat := "fmt"
	logFormat, _ = os.LookupEnv("LOG_FORMAT")

	setLogFormat(logFormat)
	akv2k8s.LogVersion()

	// set up signals so we handle the first shutdown signal gracefully
	// stopCh := signals.SetupSignalHandler()
	setLogLevel()

	cfg, err := clientcmd.BuildConfigFromFlags(masterURL, kubeconfig)
	if err != nil {
		log.Fatalf("Error building kubeconfig: %s", err.Error())
	}

	kubeClient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("Error building kubernetes clientset: %s", err.Error())
	}

	// identityClient, err := clientset.NewForConfig(cfg)
	// if err != nil {
	// 	log.Fatalf("Error building azureKeyVaultSecret clientset: %s", err.Error())
	// }

	// identityInformerFactory := informers.NewSharedInformerFactory(identityClient, time.Second*30)

	log.Info("Creating event broadcaster")
	eventBroadcaster := record.NewBroadcaster()
	eventBroadcaster.StartLogging(log.Tracef)
	eventBroadcaster.StartRecordingToSink(&typedcorev1.EventSinkImpl{Interface: kubeClient.CoreV1().Events("")})

	f, err := os.Open(cloudconfig)
	if err != nil {
		log.Fatalf("Failed reading azure config from %s, error: %+v", cloudconfig, err)
	}
	defer f.Close()

	cloudCnfProvider, err := credentialprovider.NewFromCloudConfig(f)
	if err != nil {
		log.Fatalf("Failed reading azure config from %s, error: %+v", cloudconfig, err)
	}

	armAuth, err := cloudCnfProvider.GetAzureResourceManagerCredentials()
	if err != nil {
		log.Fatalf("failed to create azure resource manager credentials, error: %+v", err.Error())
	}

	if armAuth == nil {

	}
	// recorder := eventBroadcaster.NewRecorder(scheme.Scheme, corev1.EventSource{Component: controllerAgentName})

	// options := &controller.Options{
	// 	MaxNumRequeues: 5,
	// 	NumThreads:     1,
	// }

	// controller := controller.NewController(
	// 	kubeClient,
	// 	azureKeyVaultSecretClient,
	// 	azureKeyVaultSecretInformerFactory,
	// 	kubeInformerFactory,
	// 	recorder,
	// 	vaultService,
	// 	"azure-key-vault-env-injection",
	// 	azurePollFrequency,
	// 	options)

	// controller.Run(stopCh)
}

func init() {
	flag.StringVar(&version, "version", "", "Version of this component.")
	flag.StringVar(&kubeconfig, "kubeconfig", "", "Path to a kubeconfig. Only required if out-of-cluster.")
	flag.StringVar(&masterURL, "master", "", "The address of the Kubernetes API server. Overrides any value in kubeconfig. Only required if out-of-cluster.")
	flag.StringVar(&logLevel, "log-level", "", "log level")
	flag.StringVar(&cloudconfig, "cloudconfig", "/etc/kubernetes/azure.json", "Path to cloud config. Only required if this is not at default location /etc/kubernetes/azure.json")
}

func setLogFormat(logFormat string) {
	switch logFormat {
	case "fmt":
		log.SetFormatter(&log.TextFormatter{
			DisableColors: true,
			FullTimestamp: true,
		})
	case "json":
		log.SetFormatter(&log.JSONFormatter{})
	default:
		log.Warnf("Log format %s not supported - using default fmt", logFormat)
	}
}

func setLogLevel() {
	if logLevel == "" {
		var ok bool
		if logLevel, ok = os.LookupEnv("LOG_LEVEL"); !ok {
			logLevel = log.InfoLevel.String()
		}
	}

	logrusLevel, err := log.ParseLevel(logLevel)
	if err != nil {
		log.Fatalf("Error setting log level: %s", err.Error())
	}
	log.SetLevel(logrusLevel)
	log.Printf("Log level set to '%s'", logrusLevel.String())
}
