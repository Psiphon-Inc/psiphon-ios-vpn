#!/usr/bin/python
#
# Copyright (c) 2011, Psiphon Inc.
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import os
import shlex
import subprocess
import sys
import psi_ops_config
import time
import logging


MAX_RETRIES = 3
RETRY_SLEEP_TIME = 150


def export_ciphershare_document(ciphershare_document_path, export_file_path):
    """Exports ciphershare document with path `ciphershare_document_path` as file `export_file_path`."""

    try:
        # Can't overwrite target file directly due to Wine limitation
        export_temp_file_path = export_file_path + '.temp'

        # If a file exists at the desired temp export path delete it
        if os.path.isfile(export_temp_file_path):
            logging.info('Removing temp file: %s', export_temp_file_path)
            os.remove(export_temp_file_path)

        cmd = 'wine %s \
                ExportDocument \
                -UserName %s -Password %s \
                -OfficeName %s -DatabasePath "%s" -ServerHost %s -ServerPort %s \
                -SourceDocument "%s" \
                -TargetFile "%s"' \
             % (psi_ops_config.CIPHERSHARE_SCRIPTING_CLIENT_EXE_PATH,
                psi_ops_config.CIPHERSHARE_USERNAME,
                psi_ops_config.CIPHERSHARE_PASSWORD,
                psi_ops_config.CIPHERSHARE_OFFICENAME,
                psi_ops_config.CIPHERSHARE_DATABASEPATH,
                psi_ops_config.CIPHERSHARE_SERVERHOST,
                psi_ops_config.CIPHERSHARE_SERVERPORT,
                ciphershare_document_path,
                export_temp_file_path)

        print cmd.replace(psi_ops_config.CIPHERSHARE_PASSWORD, '****')

        proc = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = proc.communicate()

        if proc.returncode != 0:
            msg = 'CipherShare export failed %s' % str(output)
            logging.warning(msg)
            raise Exception(msg)

        # Drop the .temp suffix if we successfully exported the file
        if os.path.isfile(export_temp_file_path):
            # If a file exists at the desired final export path delete it
            if os.path.isfile(export_file_path):
                os.remove(export_file_path)
                logging.info('%s removed', export_file_path)
            os.rename(export_temp_file_path, export_file_path)
            logging.info('%s renamed to %s', export_temp_file_path, export_file_path)
        else:
            logging.info('%s is not found', export_temp_file_path)
            logging.info('%s, %s', proc.stdout, proc.stderr)

    except Exception as e:
        logging.warning('Exception: %s', str(e))
        print str(e)


def main():
    logging.basicConfig(filename='psi_export_doc.log', format='%(asctime)s %(levelname)s %(message)s', level=logging.DEBUG)

    # Mapping of the paths of CipherShare documents to be exported to the desired output file path
    # '<path of ciphershare document to export>': '<path of output file>'
    # e.g.: 'Windows\Path\To\CipherShare\Document': os.path.abspath('./MyExportedDocument')
    for ciphershare_document_path, export_file_path in psi_ops_config.CIPHERSHARE_TARGET_DOCUMENTS_FOR_EXPORT.items(): 
        count = 0
        file_ctime = None

        if os.path.exists(export_file_path):
            file_ctime = os.path.getctime(export_file_path)

        while count < MAX_RETRIES:
            export_ciphershare_document(ciphershare_document_path, export_file_path)
            if os.path.getctime(export_file_path) > file_ctime:
                break
            else:
                count += 1
                if count == MAX_RETRIES:
                    logging.info('MAX_RETRIES exceeded for file: %s. Exiting...', ciphershare_document_path)
                    sys.exit(1)
                else:
                    logging.info('Failed to export file: %s. Attempt %s/%s failed. Sleeping for %s seconds before retrying...', ciphershare_document_path, count-1, MAX_RETRIES, RETRY_SLEEP_TIME)
                    time.sleep(RETRY_SLEEP_TIME)


if __name__ == "__main__":
    main()

