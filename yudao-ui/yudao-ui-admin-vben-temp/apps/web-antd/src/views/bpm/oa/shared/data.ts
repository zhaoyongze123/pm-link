import type { VbenFormSchema } from '#/adapter/form';
import type { VxeTableGridOptions } from '#/adapter/vxe-table';
import type { DescriptionItemSchema } from '#/components/description';

import { DICT_TYPE } from '@vben/constants';
import { getDictLabel, getDictOptions } from '@vben/hooks';
import { formatDate } from '@vben/utils';
import { getRangePickerDefaultProps } from '#/utils';

import type { OAModuleViewConfig } from './config';

function getFallbackTypeLabel(
  config: OAModuleViewConfig,
  value: null | number | string | undefined,
) {
  if (value === undefined || value === null) {
    return '-';
  }
  const matched = config.fallbackTypeOptions?.find(
    (item) => String(item.value) === String(value),
  );
  return matched?.label || String(value);
}

function useFormSchema(config: OAModuleViewConfig): VbenFormSchema[] {
  const typeLabel = `${config.title}类型`;
  const reasonLabel = `${config.title}原因`;

  return [
    {
      fieldName: 'type',
      label: typeLabel,
      component: 'Select',
      componentProps: {
        placeholder: `请选择${typeLabel}`,
        options: getDictOptions(config.dictType, 'number'),
        allowClear: true,
      },
      rules: 'required',
    },
    {
      fieldName: 'startTime',
      label: '开始时间',
      component: 'DatePicker',
      componentProps: {
        placeholder: '请选择开始时间',
        showTime: true,
        valueFormat: 'x',
        format: 'YYYY-MM-DD HH:mm:ss',
      },
      rules: 'required',
    },
    {
      fieldName: 'endTime',
      label: '结束时间',
      component: 'DatePicker',
      componentProps: {
        placeholder: '请选择结束时间',
        showTime: true,
        valueFormat: 'x',
        format: 'YYYY-MM-DD HH:mm:ss',
      },
      rules: 'required',
    },
    {
      fieldName: 'reason',
      label: reasonLabel,
      component: 'Textarea',
      componentProps: {
        placeholder: `请输入${reasonLabel}`,
      },
      rules: 'required',
    },
  ];
}

function useGridFormSchema(config: OAModuleViewConfig): VbenFormSchema[] {
  return [
    {
      fieldName: 'type',
      label: `${config.title}类型`,
      component: 'Select',
      componentProps: {
        placeholder: `请选择${config.title}类型`,
        options: getDictOptions(config.dictType, 'number'),
        allowClear: true,
      },
    },
    {
      fieldName: 'createTime',
      label: '创建时间',
      component: 'RangePicker',
      componentProps: {
        ...getRangePickerDefaultProps(),
        allowClear: true,
      },
    },
    {
      fieldName: 'status',
      label: '审批结果',
      component: 'Select',
      componentProps: {
        placeholder: '请选择审批结果',
        allowClear: true,
        options: getDictOptions(
          DICT_TYPE.BPM_PROCESS_INSTANCE_STATUS,
          'number',
        ),
      },
    },
    {
      fieldName: 'reason',
      label: `${config.title}原因`,
      component: 'Input',
      componentProps: {
        placeholder: `请输入${config.title}原因`,
        allowClear: true,
      },
    },
  ];
}

function useGridColumns(
  config: OAModuleViewConfig,
): VxeTableGridOptions['columns'] {
  return [
    {
      field: 'id',
      title: '申请编号',
      minWidth: 100,
    },
    {
      field: 'status',
      title: '状态',
      minWidth: 100,
      cellRender: {
        name: 'CellDict',
        props: { type: DICT_TYPE.BPM_PROCESS_INSTANCE_STATUS },
      },
    },
    {
      field: 'startTime',
      title: '开始时间',
      minWidth: 180,
      formatter: 'formatDate',
    },
    {
      field: 'endTime',
      title: '结束时间',
      minWidth: 180,
      formatter: 'formatDate',
    },
    {
      field: 'type',
      title: `${config.title}类型`,
      minWidth: 120,
      cellRender: {
        name: 'CellDict',
        props: { type: config.dictType },
      },
    },
    {
      field: 'reason',
      title: `${config.title}原因`,
      minWidth: 150,
    },
    {
      field: 'createTime',
      title: '申请时间',
      minWidth: 180,
      formatter: 'formatDateTime',
    },
    {
      title: '操作',
      width: 240,
      fixed: 'right',
      slots: { default: 'actions' },
    },
  ];
}

function useDetailFormSchema(
  config: OAModuleViewConfig,
): DescriptionItemSchema[] {
  return [
    {
      label: `${config.title}类型`,
      field: 'type',
      render: (val) =>
        val === undefined || val === null
          ? '-'
          : getDictLabel(config.dictType, val) || getFallbackTypeLabel(config, val),
    },
    {
      label: '开始时间',
      field: 'startTime',
      render: (val) => formatDate(val) as string,
    },
    {
      label: '结束时间',
      field: 'endTime',
      render: (val) => formatDate(val) as string,
    },
    {
      label: `${config.title}原因`,
      field: 'reason',
    },
  ];
}

export {
  useDetailFormSchema,
  useFormSchema,
  useGridColumns,
  useGridFormSchema,
};
