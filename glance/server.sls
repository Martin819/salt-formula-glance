{%- from "glance/map.jinja" import server with context %}
{%- if server.enabled %}

glance_packages:
  pkg.installed:
  - names: {{ server.pkgs }}

{%- if not salt['user.info']('glance') %}
glance_user:
  user.present:
    - name: glance
    - home: /var/lib/glance
    - uid: 302
    - gid: 302
    - shell: /bin/false
    - system: True
    - require_in:
      - pkg: glance_packages

glance_group:
  group.present:
    - name: glance
    - gid: 302
    - system: True
    - require_in:
      - pkg: glance_packages
      - user: glance_user
{%- endif %}

/etc/glance/glance-cache.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-cache.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-registry.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-registry.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-scrubber.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-scrubber.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-api.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-api.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-api-paste.ini:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-api-paste.ini
  - template: jinja
  - require:
    - pkg: glance_packages

{%- if server.version == 'newton' %}

/etc/glance/glance-glare-paste.ini:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-glare-paste.ini
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-glare.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-glare.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

{%- if not grains.get('noservices', False) %}

glance_glare_service:
  service.running:
  - enable: true
  - name: glance-glare
  - require_in:
    - cmd: glance_install_database
  - watch:
    - file: /etc/glance/glance-glare.conf

{%- endif %}
{%- endif %}

{%- if not grains.get('noservices', False) %}

glance_services:
  service.running:
  - enable: true
  - names: {{ server.services }}
  - watch:
    - file: /etc/glance/glance-api.conf
    - file: /etc/glance/glance-registry.conf
    - file: /etc/glance/glance-api-paste.ini

glance_install_database:
  cmd.run:
  - name: glance-manage db_sync
  - require:
    - service: glance_services

{%- if server.get('image_cache', {}).get('enabled', False) %}
glance_cron_glance-cache-pruner:
  cron.present:
  - name: glance-cache-pruner
  - user: glance
  - special: '@daily'
  - require:
    - service: glance_services

glance_cron_glance-cache-cleaner:
  cron.present:
  - name: glance-cache-cleaner
  - user: glance
  - minute: 30
  - hour: 5
  - daymonth: '*/2'
  - require:
    - service: glance_services

{%- endif %}

{%- endif %}

{%- if grains.get('virtual_subtype', None) == "Docker" %}

glance_entrypoint:
  file.managed:
  - name: /entrypoint.sh
  - template: jinja
  - source: salt://glance/files/entrypoint.sh
  - mode: 755

{%- endif %}

/var/lib/glance/images:
  file.directory:
  - mode: 755
  - user: glance
  - group: glance
  - require:
    - pkg: glance_packages

{%- for image in server.get('images', []) %}

glance_download_{{ image.name }}:
  cmd.run:
  - name: wget {{ image.source }}
  - unless: "test -e {{ image.file }}"
  - cwd: /srv/glance
  - require:
    - file: /srv/glance

glance_install_{{ image.name }}:
  cmd.wait:
  - name: source /root/keystonerc; glance image-create --name '{{ image.name }}' --is-public {{ image.public }} --container-format bare --disk-format {{ image.format }} < {{ image.file }}
  - cwd: /srv/glance
  - require:
    - service: glance_services
  - watch:
    - cmd: glance_download_{{ image.name }}

{%- endfor %}

{%- for image_name, image in server.get('image', {}).iteritems() %}

glance_download_{{ image_name }}:
  cmd.run:
  - name: wget {{ image.source }}
  - unless: "test -e {{ image.file }}"
  - cwd: /srv/glance
  - require:
    - file: /srv/glance

glance_install_image_{{ image_name }}:
  cmd.run:
  - name: source /root/keystonerc; glance image-create --name '{{ image_name }}' --is-public {{ image.public }} --container-format bare --disk-format {{ image.format }} < /srv/glance/{{ image.file }}
  - require:
    - service: glance_services
    - cmd: glance_download_{{ image_name }}
  - unless:
    - cmd: source /root/keystonerc && glance image-list | grep {{ image_name }}

{%- endfor %}

{%- if server.policy is defined %}

{%- for key, policy in server.policy.iteritems() %}

policy_{{ key }}:
  file.replace:
  - name: /etc/glance/policy.json
  - pattern: "[\"']{{ key }}[\"']:.*"
  {# unfortunatately there's no jsonify filter so we have to do magic :-( #}
  - repl: '"{{ key }}": {% if policy is iterable %}[{%- for rule in policy %}"{{ rule }}"{% if not loop.last %}, {% endif %}{%- endfor %}]{%- else %}"{{ policy }}"{%- endif %},'

{%- endfor %}

{%- endif %}

{%- endif %}
