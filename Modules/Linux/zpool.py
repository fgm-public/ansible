
#!/usr/bin/python

# -*- coding: utf-8 -*-

# Copyright: (c) 2019, Gennadiy Fetisov <fgm.public@gmail.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import absolute_import, division, print_function
__metaclass__ = type

ANSIBLE_METADATA = {'metadata_version': '1.1',
                    'status': ['preview'],
                    'supported_by': 'not_supported'}

DOCUMENTATION = '''
---
module: zpool
short_description: Manage zfs pools
description:
  - Manages ZFS pools
options:
  name:
    description:
      - ZFS pool name. C(rpool).
    required: true
    default: zp1
  state:
    description:
      - Whether to create (C(present)), or remove (C(absent)) a
        ZFS pool. All children will be destroyed as needed to 
        reach the desired state.
    choices: [ absent, present ]
    required: true
    default: present
  reservation:
    description:
      - Creates dataset with amount of space in Gb
        to prevent performance degradation due to pool filling.
    required: false
    default: 80
  properties:
    description:
      - A dictionary of ZFS pool properties to be set.
      - See the zfs(8) man page for more information.
    required: false
  disks:
    description:
      - A dictionary of disks labels.
    required: true
  vdev:
    description:
      - A dictionary of ZFS pool properties to be set.
      - See the zfs(8) man page for more information.
    choices: [ mirror, raidz, raidz2, raidz3 ]
    required: true
    default: mirror
author:
- Gennadiy Fetisov (fgm.public@gmail.com)
'''

EXAMPLES = '''
- name: |
    Create a new ZFS pool called 'tank'
    two mirror vdevs [sdb, sdc] and [sdd, sde]
    with the ashift 12 (for 4Kb physical sector)
    lz4 compression type and 100Gb space reservation
  zpool:
    name: tank
    state: present
    reservation: 100G
    vdev: mirror
    disks:
      - vdev1:
        - sdb
        - sdc
      - vdev2:
        - sdd
        - sde
    properties:
      ashift: 12
      compression: lz4
- name: Destroy a ZFS pool called 'tank'
  zpool:
    name: tank
    state: absent
'''

import os
from ansible.module_utils.basic import AnsibleModule
#from ansible.module_utils.basic import *

params = {
    #Be attentive! 'required' and 'default' are mutually exclusive for name
        "name": {
            "required": True,
            #"default": 'zp1',
            "type": "str"
        },
        "state": {
            "required": True,
            #"default": "present", 
            "choices": ['present', 'absent'],  
            "type": 'str' 
        },
        "reservation": {
            "required": False,
            #"default": 80,
            "type": "str"
        },
        "props": {
            "required": False,
            "type": "dict"
        },
        "disks": {
            "required": True,
            "type": "list"
        },
        "vdev": {
            "required": True,
            #"default": "mirror", 
            "choices": ['mirror', 'raidz', 'raidz2', 'raidz3'],
            "type": "str"
        },
}

module = AnsibleModule(argument_spec = params)

zpool_cmd = module.get_bin_path('zpool', True)
zfs_cmd =  module.get_bin_path('zfs', True)

def zpool_exists():

    pool_name = module.params['name']

    cmd = [zpool_cmd, 'list', pool_name]

    (rc, out, err) = module.run_command(' '.join(cmd))

    if rc == 0:
        return True
    else:
        return False


def zpool_present():

    props = module.params['props']
    pool_name = module.params['name']
    vdev_type = module.params['vdev']
    disks = module.params['disks']
    reserv = module.params['reservation']

    if not zpool_exists():

        #ids = os.listdir(/dev/disk/by-id)
        blocks = {os.readlink("/dev/disk/by-id/%s"%(id))[-3:]:id
            for id in os.listdir("/dev/disk/by-id")
                if id.count('scsi') and not id.count('part')}
        #disks = [block for block in blocks if block.isalpha()]
        #disks = [block for block in blocks if block in outer]

        cmd = [zpool_cmd, 'create']

        if props:
            for p, v in props.items():
                cmd.append('-o %s=%s' % (p, v))

        cmd.append(pool_name)

        for vdev in disks:
            cmd.append(vdev_type)
            for disk in vdev.values():
                for d in disk:
                    cmd.append(blocks.get(d))

        (rc, out, err) = module.run_command(' '.join(cmd))

        if reserv:
            cmd = [zfs_cmd, 'create', '%s/reserved'%(pool_name)]
            cmd.append('-o reservation=%s' % (reserv))
            (rc, out, err) = module.run_command(' '.join(cmd))


        if rc == 0:
            return False, True, out
        else:
            return True, False, err#module.fail_json(msg = err)

    else:
        return True, False, "Pool '%s' already exists" % pool_name


def zpool_absent():

    pool_name = module.params['name']

    if zpool_exists():

        cmd = [zpool_cmd, 'destroy', '-f', pool_name]
        (rc, out, err) = module.run_command(' '.join(cmd))
        if rc == 0:
            return False, True, out #'zpool was successfully destroyed'
        else:
            return True, False, err#module.fail_json(msg = err)

    else:
        return True, False, "Can't find '%s' pool" % pool_name


def main():

    choice_map = {
        "present": zpool_present,
        "absent": zpool_absent, 
    }

    has_failed, has_changed, result = choice_map.get(module.params['state'])()

    module.exit_json(
        failed = has_failed,
        changed = has_changed,
        meta = result
    )

if __name__ == '__main__':
    main()