#!/usr/bin/env python3
"""
Autobrr configuration script for NixOS media stack.
Configures download clients, RSS feeds and filters for automatic free torrent grabbing.
"""

import requests
import os
import sys
import json

def get_secret(path):
    """Read secret from file."""
    if not path or not os.path.exists(path):
        return None
    with open(path, 'r') as f:
        return f.read().strip()

def setup_qbittorrent_client(base_url, headers, qbit_port, qbit_pass):
    """Setup qBittorrent as download client in Autobrr."""
    try:
        resp = requests.get(f"{base_url}/api/config/download-clients", headers=headers)
        existing = resp.json() if resp.status_code == 200 else []
        qbit_id = None
        
        for c in existing:
            if isinstance(c, dict) and c.get('name') == 'qBit':
                qbit_id = c.get('id')
                break
        
        if not qbit_id:
            resp = requests.post(f"{base_url}/api/config/download-clients", headers=headers, json={
                'name': 'qBit',
                'type': 'qBittorrent',
                'host': '127.0.0.1',
                'port': qbit_port,
                'username': 'i',
                'password': qbit_pass,
                'enabled': True
            })
            if resp.status_code in (200, 201):
                qbit_id = resp.json().get('id')
            print(f"Added qBit to Autobrr, id={qbit_id}")
        else:
            print(f"qBit already exists in Autobrr, id={qbit_id}")
        
        return qbit_id
    except Exception as e:
        print(f"Failed to setup Autobrr qBit: {e}")
        return None

def setup_rss_feeds(base_url, headers, mteam_rss, pttime_rss):
    """Setup RSS feeds for PT sites."""
    try:
        resp = requests.get(f"{base_url}/api/feeds", headers=headers)
        existing = resp.json() if resp.status_code == 200 else []
        existing_names = []
        for item in existing:
            if isinstance(item, dict):
                existing_names.append(item.get('name', ''))
        
        feed_ids = {}
        for item in existing:
            if isinstance(item, dict) and item.get('name') in ('M-Team', 'PTTime'):
                feed_ids[item.get('name')] = item.get('id')
        
        if mteam_rss and 'M-Team' not in existing_names:
            resp = requests.post(f"{base_url}/api/feeds", headers=headers, json={
                'name': 'M-Team',
                'type': 'TORZNAB',
                'url': mteam_rss,
                'interval': 15,
                'enabled': True
            })
            if resp.status_code in (200, 201):
                feed_ids['M-Team'] = resp.json().get('id')
                print("Added M-Team RSS feed")
        
        if pttime_rss and 'PTTime' not in existing_names:
            resp = requests.post(f"{base_url}/api/feeds", headers=headers, json={
                'name': 'PTTime',
                'type': 'TORZNAB',
                'url': pttime_rss,
                'interval': 15,
                'enabled': True
            })
            if resp.status_code in (200, 201):
                feed_ids['PTTime'] = resp.json().get('id')
                print("Added PTTime RSS feed")
        
        return feed_ids
    except Exception as e:
        print(f"Failed to setup Autobrr feeds: {e}")
        return {}

def setup_free_grabber_filter(base_url, headers, qbit_id, feed_ids):
    """Setup filter for grabbing free torrents."""
    try:
        resp = requests.get(f"{base_url}/api/filters", headers=headers)
        existing = resp.json() if resp.status_code == 200 else []
        existing_names = []
        for item in existing:
            if isinstance(item, dict):
                existing_names.append(item.get('name', ''))
        
        if 'Auto-Free-Grabber' not in existing_names and qbit_id:
            action_list = [{
                'name': 'qBit-Free',
                'type': 'QBITTORRENT',
                'enabled': True,
                'client_id': qbit_id,
                'save_path': '/data/downloads/torrents/prowlarr',
                'category': 'prowlarr',
                'paused': False
            }]
            indexer_list = list(feed_ids.values()) if feed_ids else []
            
            resp = requests.post(f"{base_url}/api/filters", headers=headers, json={
                'name': 'Auto-Free-Grabber',
                'enabled': True,
                'priority': 10,
                'min_size': '100MB',
                'max_size': '50GB',
                'freeleech': True,
                'freeleech_percent': '100%',
                'actions': action_list,
                'indexers': indexer_list
            })
            print(f"Created Auto-Free-Grabber filter: {resp.status_code}")
        else:
            print("Auto-Free-Grabber filter already exists or no qbit client")
    except Exception as e:
        print(f"Failed to setup Autobrr filters: {e}")

def main():
    """Main entry point."""
    if len(sys.argv) < 6:
        print("Usage: autobrr_setup.py <base_url> <api_key_file> <password_file> <qbit_port> <mteam_rss_file> <pttime_rss_file>")
        sys.exit(1)
    
    base_url = sys.argv[1]
    api_key = get_secret(sys.argv[2])
    password = get_secret(sys.argv[3])
    qbit_port = int(sys.argv[4])
    mteam_rss = get_secret(sys.argv[5]) if len(sys.argv) > 5 else None
    pttime_rss = get_secret(sys.argv[6]) if len(sys.argv) > 6 else None
    
    if not api_key:
        print("Missing API key")
        sys.exit(1)
    
    headers = {'X-API-Token': api_key}
    
    # Setup qBittorrent client
    qbit_id = setup_qbittorrent_client(base_url, headers, qbit_port, password)
    
    # Setup RSS feeds
    feed_ids = setup_rss_feeds(base_url, headers, mteam_rss, pttime_rss)
    
    # Setup free grabber filter
    setup_free_grabber_filter(base_url, headers, qbit_id, feed_ids)
    
    print("Autobrr configuration completed")

if __name__ == '__main__':
    main()
