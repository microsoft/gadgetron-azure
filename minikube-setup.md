# Minikube for Gadgetron

[Minikube](https://kubernetes.io/docs/tutorials/hello-minikube) is a single node cluster you can run on your personal computer for testing. Here are just a few notes on how to set up Minikube and some specific guidance for Windows WSL2 if that is your environment.

Minikube is easily installed with:

```bash
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && chmod +x minikube
```

Move the `minikube` executable to a suitable location on your box. You can then start minikube with:

```bash
minikube start
```

If you are using [WSL2](https://docs.microsoft.com/en-us/windows/wsl/wsl2-index) and [Docker for WSL2](https://docs.docker.com/docker-for-windows/wsl/), you can start minikube with:


```bash
minikube start --vm-driver=docker
```

After starting minikube, enable `metrics-server` with:

```bash
minikube addons enable metrics-server
```

Or simply enable it during startup:

```bash
minikube start --vm-driver=docker --addons=metrics-server
```

Finally, you should add the latest stable helm charts repo:

```bash
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
```