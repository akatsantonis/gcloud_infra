gcp_region         = "us-east1"
network            = "main"
lb_service_account = "load-balancer"
lb_node_defaults = {
  machine_type        = "e2-micro"
  image_family        = "load-balancer"
  disk_size           = 10
  disk_type           = "pd-standard"
  role                = "k8s-load-balancer"
  tags                = ["ssh", "icmp", "k8s-load-balancer"]
  startup_script      = ""
  startup_script_data = {}
  cloud_init          = "k8s-lb.yaml"
  cloud_init_data     = {}
}
lb_nodes = [
  {
    name = "k8s-lb-1"
    cloud_init_data = {
      lb_state = "MASTER"
      lb_prio  = "104"
    }
  },
  {
    name = "k8s-lb-2"
    cloud_init_data = {
      lb_state = "BACKUP"
      lb_prio  = "103"
    }
  }
]

k8s_node_defaults = {
  machine_type        = "e2-medium"
  image_family        = "k8s-node"
  disk_size           = 10
  disk_type           = "pd-standard"
  role                = ""
  tags                = []
  startup_script      = ""
  startup_script_data = {}
  cloud_init          = "k8s-join.yaml"
  cloud_init_data = {
    k8s-secret  = "k8s-secret"
    filter-env  = "testing"
    filter-role = "k8s-master"
  }
}
k8s_nodes = [
  {
    name       = "k8s-master-1"
    cloud_init = "k8s-init.yaml"
    role       = "k8s-master"
    tags       = ["ssh", "icmp", "calico-vxlan", "k8s-master", "k8s-worker"]
  },
  {
    name = "k8s-worker-1"
    role = "k8s-worker"
    tags = ["ssh", "icmp", "calico-vxlan", "k8s-worker"]
  }
]

admin_ssh_keys = [
  "aka:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICXCS1q9tidu+NWd4JCu+vOozjefnxTAa1hwkdizf/0M 06042025",
  "ansible:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJI1QdTQkaL/+CRzCTUlrKHLAQWRxjVdR5Y1C0FA3o2a 06042025"
]
