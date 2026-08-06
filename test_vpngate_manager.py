import unittest

import vpngate_manager as manager


class NodeQualityTests(unittest.TestCase):
    def test_residential_ip_passes_purity_policy(self) -> None:
        node = manager.apply_purity_score(
            {
                "ip_type": "residential",
                "quality": "normal",
                "owner": "NTT Communications",
                "as_name": "NTT",
            }
        )
        self.assertEqual(node["purity_status"], "high")
        self.assertTrue(manager.node_quality_allowed(node))

    def test_cloud_provider_is_rejected_even_when_classified_residential(self) -> None:
        node = manager.apply_purity_score(
            {
                "ip_type": "residential",
                "quality": "normal",
                "owner": "Amazon Web Services",
                "as_name": "AWS",
            }
        )
        self.assertEqual(node["purity_status"], "low")
        self.assertFalse(manager.node_quality_allowed(node))


class NodeLifecycleTests(unittest.TestCase):
    def test_probe_selection_rotates_upstream_sources(self) -> None:
        nodes = []
        for source in ("AutoOVPN", "VPNGate", "IPSpeed"):
            for index in range(3):
                nodes.append(
                    {
                        "id": f"{source}-{index}",
                        "source": "publicvpnlist",
                        "upstream_source": source,
                        "ip": f"192.0.2.{len(nodes) + 1}",
                        "remote_port": 443,
                        "proto": "tcp",
                    }
                )

        selected = manager.select_nodes_for_probe(nodes, 6)
        self.assertEqual(
            [node["upstream_source"] for node in selected],
            ["AutoOVPN", "VPNGate", "IPSpeed", "AutoOVPN", "VPNGate", "IPSpeed"],
        )

    def test_unchecked_node_is_scheduled_before_recent_success(self) -> None:
        nodes = [
            {
                "id": "recent",
                "source": "publicvpnlist",
                "upstream_source": "AutoOVPN",
                "ip": "192.0.2.20",
                "remote_port": 443,
                "proto": "tcp",
                "probe_status": "available",
                "last_probe_at": manager.time.time(),
            },
            {
                "id": "new",
                "source": "publicvpnlist",
                "upstream_source": "AutoOVPN",
                "ip": "192.0.2.21",
                "remote_port": 443,
                "proto": "tcp",
                "probe_status": "not_checked",
                "last_probe_at": 0,
            },
        ]

        selected = manager.select_nodes_for_probe(nodes, 1)
        self.assertEqual(selected[0]["id"], "new")

    def test_merge_preserves_probe_history_for_same_endpoint(self) -> None:
        previous = {
            "id": "old",
            "ip": "198.51.100.10",
            "remote_port": 443,
            "proto": "tcp",
            "first_seen_at": 100,
            "probe_status": "available",
            "probe_successes": 4,
            "purity_score": 88,
            "purity_status": "high",
            "config_text": "client\n",
        }
        candidate = {
            "id": "new",
            "ip": "198.51.100.10",
            "remote_port": 443,
            "proto": "tcp",
            "probe_status": "not_checked",
        }

        merged = manager.merge_node_history(candidate, previous)
        self.assertEqual(merged["first_seen_at"], 100)
        self.assertEqual(merged["probe_status"], "available")
        self.assertEqual(merged["probe_successes"], 4)
        self.assertEqual(merged["purity_score"], 88)
        self.assertEqual(merged["config_text"], "client\n")


if __name__ == "__main__":
    unittest.main()
