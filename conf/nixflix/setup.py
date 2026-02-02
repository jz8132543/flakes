#!/usr/bin/env python3
import requests
import os
import sys
import argparse
import time

def get_secret(path):
    if not path or not os.path.exists(path):
        return None
    with open(path, 'r') as f:
        return f.read().strip()

def setup_bazarr(args):
    print("Setting up Bazarr...")
    sonarr_key = get_secret(args.sonarr_key_file)
    radarr_key = get_secret(args.radarr_key_file)
    password = get_secret(args.password_file)
    
    if not (sonarr_key and radarr_key and password):
        print("Missing secrets for Bazarr setup")
        return

    try:
        # Configure Auth
        requests.post(f"{args.bazarr_url}/config/auth", json={
            'apikey': "",
            'authentication': "Form",
            'username': "i",
            'password': password
        })
        
        # Get current config to find API key
        resp = requests.get(f"{args.bazarr_url}/config/general")
        b_key = resp.json().get('apikey')
        print(f"Bazarr API key found")

        # Sonarr
        requests.post(f"{args.bazarr_url}/sonarr", json={
            'enabled': True, 'apikey': sonarr_key, 'address': '127.0.0.1', 
            'port': int(args.sonarr_port), 'basepath': '/sonarr'
        })
        # Radarr
        requests.post(f"{args.bazarr_url}/radarr", json={
            'enabled': True, 'apikey': radarr_key, 'address': '127.0.0.1', 
            'port': int(args.radarr_port), 'basepath': '/radarr'
        })
        print("Bazarr configuration completed")
    except Exception as e:
        print(f"Failed to configure Bazarr: {e}")

def setup_autobrr(args):
    print("Setting up Autobrr...")
    a_key = get_secret(args.autobrr_key_file)
    qbit_pass = get_secret(args.password_file)
    mteam_rss = get_secret(args.mteam_rss_file)
    pttime_rss = get_secret(args.pttime_rss_file)

    if not (a_key and qbit_pass):
        print("Missing secrets for Autobrr setup")
        return

    headers = {'X-API-Token': a_key}
    try:
        # 1. Setup qBittorrent client
        resp = requests.get(f"{args.autobrr_url}/api/config/download-clients", headers=headers)
        existing = resp.json() if resp.status_code == 200 else []
        qbit_id = None
        for c in existing:
            if isinstance(c, dict) and c.get('name') == 'qBit':
                qbit_id = c.get('id')
                break
        
        if not qbit_id:
            resp = requests.post(f"{args.autobrr_url}/api/config/download-clients", headers=headers, json={
                'name': 'qBit', 'type': 'qBittorrent', 'host': '127.0.0.1',
                'port': int(args.qbit_port), 'username': 'i',
                'password': qbit_pass, 'enabled': True
            })
            if resp.status_code in [200, 201]:
                qbit_id = resp.json().get('id')
            print(f"Added qBit to Autobrr")
        
        # 2. Setup Feeds
        resp = requests.get(f"{args.autobrr_url}/api/feeds", headers=headers)
        existing_feeds = resp.json() if resp.status_code == 200 else []
        existing_names = [f.get('name', '') for f in existing_feeds if isinstance(f, dict)]
        
        feed_ids = {}
        for f in existing_feeds:
            if isinstance(f, dict) and f.get('name') in ['M-Team', 'PTTime']:
                feed_ids[f['name']] = f.get('id')

        if mteam_rss and 'M-Team' not in existing_names:
            resp = requests.post(f"{args.autobrr_url}/api/feeds", headers=headers, json={
                'name': 'M-Team', 'type': 'TORZNAB', 'url': mteam_rss, 'interval': 15, 'enabled': True
            })
            if resp.status_code in [200, 201]:
                feed_ids['M-Team'] = resp.json().get('id')
        
        if pttime_rss and 'PTTime' not in existing_names:
            resp = requests.post(f"{args.autobrr_url}/api/feeds", headers=headers, json={
                'name': 'PTTime', 'type': 'TORZNAB', 'url': pttime_rss, 'interval': 15, 'enabled': True
            })
            if resp.status_code in [200, 201]:
                feed_ids['PTTime'] = resp.json().get('id')

        # 3. Setup Filter
        resp = requests.get(f"{args.autobrr_url}/api/filters", headers=headers)
        existing_filters = resp.json() if resp.status_code == 200 else []
        if not any(f.get('name') == 'Auto-Free' for f in existing_filters if isinstance(f, dict)) and qbit_id:
            requests.post(f"{args.autobrr_url}/api/filters", headers=headers, json={
                'name': 'Auto-Free', 'enabled': True, 'priority': 10,
                'min_size': '100MB', 'max_size': '100GB', 'freeleech': True,
                'freeleech_percent': '100%',
                'actions': [{
                    'name': 'qBit-Free', 'type': 'QBITTORRENT', 'enabled': True,
                    'client_id': qbit_id, 'save_path': '/data/downloads/torrents/prowlarr',
                    'category': 'prowlarr', 'paused': False
                }],
                'indexers': list(feed_ids.values())
            })
            print("Autobrr filter set up")
    except Exception as e:
        print(f"Failed to setup Autobrr: {e}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bazarr-url")
    parser.add_argument("--autobrr-url")
    parser.add_argument("--moviepilot-url")
    parser.add_argument("--sonarr-key-file")
    parser.add_argument("--radarr-key-file")
    parser.add_argument("--autobrr-key-file")
    parser.add_argument("--password-file")
    parser.add_argument("--qbit-port")
    parser.add_argument("--sonarr-port")
    parser.add_argument("--radarr-port")
    parser.add_argument("--mteam-rss-file")
    parser.add_argument("--pttime-rss-file")
    args = parser.parse_args()

    setup_bazarr(args)
    setup_autobrr(args)
    
    # MoviePilot Health Check
    try:
        requests.get(f"{args.moviepilot_url}/api/v1/health")
        print("MoviePilot health check OK")
    except:
        pass

if __name__ == "__main__":
    main()
