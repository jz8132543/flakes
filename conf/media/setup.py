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

def add_download_client(name, app_url, app_key, client_name, host, port, username, password, api_version='v3'):
    """Generic function to add qBittorrent to Sonarr/Radarr/Prowlarr"""
    print(f"Setting up Download Client for {name} ({api_version})...")
    headers = {'X-Api-Key': app_key}
    
    # Adjust endpoint based on API version
    endpoint = f"{app_url}/api/{api_version}/downloadclient"
    
    try:
        # Check existing
        resp = requests.get(endpoint, headers=headers)
        if resp.status_code != 200:
            print(f"Failed to get clients for {name}: {resp.status_code} {resp.text}")
            return

        existing = resp.json()
        if any(c.get('name') == client_name for c in existing):
            print(f"Download client {client_name} already exists in {name}")
            return

        # Add new
        fields = [
            {'name': 'host', 'value': host},
            {'name': 'port', 'value': int(port)},
            {'name': 'useSsl', 'value': False},
            {'name': 'username', 'value': username},
            {'name': 'password', 'value': password},
        ]
        
        # App-specific Category fields
        if name == 'Sonarr':
            fields.append({'name': 'tvCategory', 'value': 'sonarr'})
        elif name == 'Radarr':
            fields.append({'name': 'movieCategory', 'value': 'radarr'})
        elif name == 'Prowlarr':
            fields.append({'name': 'category', 'value': 'prowlarr'})
        elif name == 'Lidarr':
            fields.append({'name': 'musicCategory', 'value': 'music-lidarr'})
        
        payload = {
            'enable': True,
            'protocol': 1, # 1 for Torrent
            'priority': 1,
            'name': client_name,
            'implementation': 'QBittorrent',
            'implementationName': 'qBittorrent',
            'configContract': 'QBittorrentSettings',
            'fields': fields,
            'categories': [] if name == 'Prowlarr' else None,
            'supportsCategories': True if name == 'Prowlarr' else False
        }
        
        # Filter out None from payload
        payload = {k: v for k, v in payload.items() if v is not None}
        
        resp = requests.post(endpoint, headers=headers, json=payload)
        if resp.status_code in [200, 201]:
            print(f"Successfully added {client_name} to {name}")
        else:
            print(f"Failed to add client to {name}: {resp.status_code} {resp.text}")

    except Exception as e:
        print(f"Error setting up client for {name}: {e}")

def setup_prowlarr_apps(prowlarr_url, prowlarr_key, sonarr_url, sonarr_key, radarr_url, radarr_key, sonarr_anime_url=None, sonarr_anime_key=None, lidarr_url=None, lidarr_key=None):
    print("Setting up Prowlarr Applications...")
    headers = {'X-Api-Key': prowlarr_key}
    endpoint = f"{prowlarr_url}/api/v1/applications"

    try:
        resp = requests.get(endpoint, headers=headers)
        if resp.status_code != 200:
            print(f"Failed to get applications: {resp.status_code}")
            return
            
        existing = resp.json()
        existing_names = [a.get('name') for a in existing]

        # Add Sonarr
        if 'Sonarr' not in existing_names and sonarr_url and sonarr_key:
            payload = {
                'name': 'Sonarr',
                'syncLevel': 'fullSync',
                'implementation': 'Sonarr',
                'configContract': 'SonarrSettings',
                'fields': [
                    {'name': 'prowlarrUrl', 'value': 'http://127.0.0.1:9696'}, # Prowlarr internal URL
                    {'name': 'baseUrl', 'value': sonarr_url},
                    {'name': 'apiKey', 'value': sonarr_key},
                    {'name': 'syncCategories', 'value': [5000, 5010, 5030, 5040]}
                ]
            }
            r = requests.post(endpoint, headers=headers, json=payload)
            print(f"Add Sonarr: {r.status_code}")

        # Add Sonarr Anime
        if 'Sonarr Anime' not in existing_names and sonarr_anime_url and sonarr_anime_key:
            payload = {
                'name': 'Sonarr Anime',
                'syncLevel': 'fullSync',
                'implementation': 'Sonarr',
                'configContract': 'SonarrSettings',
                'fields': [
                    {'name': 'prowlarrUrl', 'value': 'http://127.0.0.1:9696'},
                    {'name': 'baseUrl', 'value': sonarr_anime_url},
                    {'name': 'apiKey', 'value': sonarr_anime_key},
                    {'name': 'syncCategories', 'value': [5070]} # Anime
                ]
            }
            r = requests.post(endpoint, headers=headers, json=payload)
            print(f"Add Sonarr Anime: {r.status_code}")

        # Add Radarr
        if 'Radarr' not in existing_names and radarr_url and radarr_key:
            payload = {
                'name': 'Radarr',
                'syncLevel': 'fullSync',
                'implementation': 'Radarr',
                'configContract': 'RadarrSettings',
                'fields': [
                    {'name': 'prowlarrUrl', 'value': 'http://127.0.0.1:9696'},
                    {'name': 'baseUrl', 'value': radarr_url},
                    {'name': 'apiKey', 'value': radarr_key},
                    {'name': 'syncCategories', 'value': [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]} # Movies
                ]
            }
            r = requests.post(endpoint, headers=headers, json=payload)
            print(f"Add Radarr: {r.status_code}")

        # Add Lidarr
        if 'Lidarr' not in existing_names and lidarr_url and lidarr_key:
            payload = {
                'name': 'Lidarr',
                'syncLevel': 'fullSync',
                'implementation': 'Lidarr',
                'configContract': 'LidarrSettings',
                'fields': [
                    {'name': 'prowlarrUrl', 'value': 'http://127.0.0.1:9696'},
                    {'name': 'baseUrl', 'value': lidarr_url},
                    {'name': 'apiKey', 'value': lidarr_key},
                    # Standard audio categories: 3000 (Audio), 3010 (MP3), 3020 (Video), 3030 (Audiobook), 3040 (Lossless)
                    {'name': 'syncCategories', 'value': [3000, 3010, 3020, 3030, 3040]}
                ]
            }
            r = requests.post(endpoint, headers=headers, json=payload)
            print(f"Add Lidarr: {r.status_code}")

    except Exception as e:
        print(f"Error setting up Prowlarr apps: {e}")

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



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bazarr-url")
    parser.add_argument("--autobrr-url")
    parser.add_argument("--prowlarr-url")
    parser.add_argument("--sonarr-url")
    parser.add_argument("--radarr-url")
    parser.add_argument("--lidarr-url")
    
    parser.add_argument("--sonarr-key-file")
    parser.add_argument("--lidarr-key-file")
    parser.add_argument("--radarr-key-file")
    parser.add_argument("--prowlarr-key-file")
    parser.add_argument("--autobrr-key-file")
    parser.add_argument("--password-file")
    parser.add_argument("--sonarr-anime-url")
    parser.add_argument("--sonarr-anime-key-file")
    
    parser.add_argument("--qbit-port")
    parser.add_argument("--sonarr-port")
    parser.add_argument("--radarr-port")
    
    parser.add_argument("--mteam-rss-file")
    parser.add_argument("--pttime-rss-file")
    args, unknown = parser.parse_known_args() # Use parse_known_args to verify other keys

    # Load Secrets
    sonarr_key = get_secret(args.sonarr_key_file)
    radarr_key = get_secret(args.radarr_key_file)
    lidarr_key = get_secret(args.lidarr_key_file)
    prowlarr_key = get_secret(args.prowlarr_key_file)
    qbit_pass = get_secret(args.password_file)
    
    qbit_port = args.qbit_port

    # Setup Sonarr
    if args.sonarr_url and sonarr_key and qbit_pass:
        add_download_client("Sonarr", args.sonarr_url, sonarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v3')
    
    # Setup Radarr
    if args.radarr_url and radarr_key and qbit_pass:
        add_download_client("Radarr", args.radarr_url, radarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v3')

    # Setup Lidarr
    if args.lidarr_url and lidarr_key and qbit_pass:
        add_download_client("Lidarr", args.lidarr_url, lidarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v1')
        
    # Setup Sonarr Anime
    if args.sonarr_anime_url and args.sonarr_anime_key_file:
        sa_key = get_secret(args.sonarr_anime_key_file)
        if sa_key and qbit_pass:
            add_download_client("Sonarr Anime", args.sonarr_anime_url, sa_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v3')

    # Setup Prowlarr
    if args.prowlarr_url:
        if qbit_pass and prowlarr_key:
            add_download_client("Prowlarr", args.prowlarr_url, prowlarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v1')
        
        sa_key = get_secret(args.sonarr_anime_key_file) # Re-read for clarity or pass if available
        setup_prowlarr_apps(args.prowlarr_url, prowlarr_key, args.sonarr_url, sonarr_key, args.radarr_url, radarr_key, args.sonarr_anime_url, sa_key, args.lidarr_url, lidarr_key)

    if args.bazarr_url:
        setup_bazarr(args)
    


if __name__ == "__main__":
    main()
