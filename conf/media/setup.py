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
            fields.append({'name': 'tvCategory', 'value': 'tv-sonarr'})
        elif name == 'Radarr':
            fields.append({'name': 'movieCategory', 'value': 'movies-radarr'})
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

def setup_jellyfin(args):
    print("Setting up Jellyfin...")
    password = get_secret(args.password_file)
    if not password:
        print("Missing password for Jellyfin setup")
        return

    try:
        # 1. Authenticate to get Access Token
        auth_url = f"{args.jellyfin_url}/Users/AuthenticateByName"
        headers = {
            'X-Emby-Authorization': 'MediaBrowser Client="Jellyfin Script", Device="NixOS", DeviceId="setup-script", Version="1.0.0"'
        }
        
        # Initial auth
        auth_payload = {
            "Username": "i",
            "Pw": password
        }
        
        resp = requests.post(auth_url, json=auth_payload, headers=headers)
        if resp.status_code != 200:
            print(f"Jellyfin Auth Failed: {resp.status_code} {resp.text}")
            return

        auth_data = resp.json()
        access_token = auth_data.get('AccessToken')
        # user_id = auth_data.get('User', {}).get('Id')
        
        if not access_token:
            print("Failed to get AccessToken from Jellyfin")
            return

        # Update headers with token
        headers['X-Emby-Token'] = access_token

        # 2. Check for existing Homepage Key
        # API Keys are listed under /Auth/Keys
        keys_url = f"{args.jellyfin_url}/Auth/Keys"
        
        keys_resp = requests.get(keys_url, headers=headers)
        homepage_key = None
        
        if keys_resp.status_code == 200:
            items = keys_resp.json().get('Items', [])
            print(f"Existing keys: {[i.get('AppName') for i in items]}")
            for item in items:
                if item.get('AppName') == 'Homepage':
                    homepage_key = item.get('AccessToken')
                    print("Found existing Homepage API Key")
                    break
        
        # 3. Create if not exists
        if not homepage_key:
            # Jellyfin often expects 'app' as query param for this endpoint
            create_url = f"{keys_url}?app=Homepage"
            create_resp = requests.post(create_url, headers=headers)
            
            if create_resp.status_code in [200, 201, 204]:
                print(f"Creation response: {create_resp.status_code}")
                # Try to parse key from response if possible
                try:
                    if create_resp.text:
                        homepage_key = create_resp.json().get('AccessToken')
                except:
                    pass
                
                # If 204 or empty response, fetch list again
                if not homepage_key:
                    print("Re-fetching keys after creation...")
                    keys_resp = requests.get(keys_url, headers=headers)
                    if keys_resp.status_code == 200:
                        items = keys_resp.json().get('Items', [])
                        for item in items:
                            if item.get('AppName') == 'Homepage':
                                homepage_key = item.get('AccessToken')
                                print("Found newly created Homepage API Key")
                                break
            else:
                print(f"Failed to create Homepage key: {create_resp.status_code} {create_resp.text}")
                return

        # 4. Write to Environment File
        if homepage_key and args.jellyfin_env_file:
            # Create dir if not exists (though script runs as root)
            os.makedirs(os.path.dirname(args.jellyfin_env_file), exist_ok=True)
            
            # Read existing content to avoid overwrite if other vars are there?
            # Or just overwrite for this specific file.
            # Assuming single-purpose file.
            with open(args.jellyfin_env_file, 'w') as f:
                f.write(f"HOMEPAGE_VAR_JELLYFIN_GENERATED_KEY={homepage_key}\n")
            print(f"Written Jellyfin key to {args.jellyfin_env_file}")

    except Exception as e:
        print(f"Error setting up Jellyfin: {e}")


    except Exception as e:
        print(f"Error setting up Jellyfin: {e}")

def configure_media_management(name, url, key, api_version='v3'):
    print(f"Configuring Media Management for {name}...")
    headers = {'X-Api-Key': key}
    endpoint = f"{url}/api/{api_version}/config/mediamanagement"

    try:
        resp = requests.get(endpoint, headers=headers)
        if resp.status_code != 200:
            print(f"Failed to get media management config for {name}: {resp.status_code} {resp.text}")
            return

        config = resp.json()
        if config.get('copyUsingHardlinks') is False:
             print(f"Hardlinks already disabled for {name}")
             return

        config['copyUsingHardlinks'] = False
        
        # PUT request to update
        resp = requests.put(endpoint, headers=headers, json=config)
        if resp.status_code in [200, 202]:
            print(f"Successfully disabled hardlinks for {name}")
        else:
            print(f"Failed to update media management for {name}: {resp.status_code} {resp.text}")

    except Exception as e:
        print(f"Error configuring media management for {name}: {e}")


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
    
    parser.add_argument("--jellyfin-url")
    parser.add_argument("--jellyfin-env-file")

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
        configure_media_management("Sonarr", args.sonarr_url, sonarr_key, api_version='v3')
    
    # Setup Radarr
    if args.radarr_url and radarr_key and qbit_pass:
        add_download_client("Radarr", args.radarr_url, radarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v3')
        configure_media_management("Radarr", args.radarr_url, radarr_key, api_version='v3')

    # Setup Lidarr
    if args.lidarr_url and lidarr_key and qbit_pass:
        add_download_client("Lidarr", args.lidarr_url, lidarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v1')
        configure_media_management("Lidarr", args.lidarr_url, lidarr_key, api_version='v1')
        
    # Setup Sonarr Anime
    if args.sonarr_anime_url and args.sonarr_anime_key_file:
        sa_key = get_secret(args.sonarr_anime_key_file)
        if sa_key and qbit_pass:
            add_download_client("Sonarr Anime", args.sonarr_anime_url, sa_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v3')
            configure_media_management("Sonarr Anime", args.sonarr_anime_url, sa_key, api_version='v3')

    # Setup Prowlarr
    if args.prowlarr_url:
        if qbit_pass and prowlarr_key:
            add_download_client("Prowlarr", args.prowlarr_url, prowlarr_key, "qBit", "127.0.0.1", qbit_port, "i", qbit_pass, api_version='v1')
        
        sa_key = get_secret(args.sonarr_anime_key_file) # Re-read for clarity or pass if available
        setup_prowlarr_apps(args.prowlarr_url, prowlarr_key, args.sonarr_url, sonarr_key, args.radarr_url, radarr_key, args.sonarr_anime_url, sa_key, args.lidarr_url, lidarr_key)

    if args.bazarr_url:
        setup_bazarr(args)
    
    if args.jellyfin_url and args.jellyfin_env_file:
        setup_jellyfin(args)
    


if __name__ == "__main__":
    main()
