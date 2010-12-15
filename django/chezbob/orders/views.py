import base64, datetime, math
from decimal import Decimal
from time import strptime

from django import forms
from django.shortcuts import render_to_response, get_object_or_404
from django.core.exceptions import ObjectDoesNotExist, PermissionDenied
from django.contrib.auth.decorators import login_required, user_passes_test
from django.http import HttpResponse, HttpResponseRedirect
from chezbob.bobdb.models import BulkItem
from chezbob.orders.models import Order, OrderItem
from chezbob.shortcuts import *

from django.core.urlresolvers import reverse

##### Order tracking #####
edit_orders_required = \
    user_passes_test(lambda u: u.has_perm('bobdb.edit_orders'))

@edit_orders_required
def order_list(request):
  mes = BobMessages()
  mes['orders'] = Order.objects.all().order_by('-date')
  mes['title']  = "List of Orders"
  reverse('chezbob.orders.views.order_summary', args=(167,))
  return render_to_response('orders/order_list.html', mes)


class OrderForm(forms.Form):
  date           = forms.DateField(initial=datetime.date.today())
  description    = forms.CharField()
  amount         = forms.DecimalField()
  sales_tax_rate = forms.DecimalField(initial=0.0875)

def simp(obj):
  new = {}
  for key in obj.__dict__:
    if not key.startswith("_"):
      new[key] = obj.__dict__[key]
  return new

@edit_orders_required
def order_summary(request, order): 
  messages = BobMessages()  
  order = get_object_or_404(Order, id=int(order))
                    
  if 'ajax' in request.POST:
    if request.POST['ajax'] == 'update_bulk_price':
      bulk_id   = request.POST['bulk_id']
      new_price = request.POST['new_price']
      is_taxed  = request.POST['is_taxed']
      date      = request.POST['date']
      bulk_item = BulkItem.objects.get(bulkid = bulk_id)
      bulk_item.price = new_price
      bulk_item.taxable = is_taxed
      bulk_item.updated = date
      bulk_item.save()
      messages['new_bulk'] = simp(bulk_item)
    elif request.POST['ajax'] == 'new_order_item':
      bulk_id = request.POST['bulk_id']
      count   = request.POST['count']
      bulk_item = BulkItem.objects.get(bulkid = bulk_id)
      item = OrderItem( order = order,
                        bulk_type = bulk_item,
                        units_per_case = bulk_item.quantity,
                        cases_ordered = count,
                        case_cost = bulk_item.price,
                        crv_per_unit = bulk_item.crv_per_unit,
                        is_cost_taxed = bulk_item.taxable,
                        is_crv_taxed = bulk_item.crv_taxable )
      item.save()
      messages['new_order_item'] = simp(item)
    elif request.POST['ajax'] == 'delete_order_item':
      item_id = request.POST['item_id']
      item = OrderItem.objects.get(id = item_id)
      if item.order.id == order.id :
        item.delete()
      else:
        messages.add("Can only delete items that are part of this order")
    else:
      messages.error("unknown ajax command '%s'" % request.POST['ajax'])
    return JsonResponse(messages)
      
  
  order_form = OrderForm({'date': order.date,
                          'amount': order.amount,
                          'description': order.description,
                          'sales_tax_rate': order.tax_rate})
                          
  if 'save_details' in request.POST:
    order_form = OrderForm(request.POST)
    if order_form.is_valid():
      order.date = order_form.cleaned_data['date']
      order.description = order_form.cleaned_data['description']
      order.amount = order_form.cleaned_data['amount']
      order.tax_rate = order_form.cleaned_data['sales_tax_rate']
      order.save()
    else:
      for error_field in order_form.errors:
        messages.error("Field %s: %s" % (error_field, order_form[error_field].errors));
        
  if 'add_item' in request.POST:
    bulk_id = int(request.POST['new_item'])
    cases_count = int(request.POST['new_count'])
    bulk_item = BulkItem.objects.get(bulkid=bulk_id)
    item = OrderItem(order          = order,
                     bulk_type      = bulk_item,
                     units_per_case = bulk_item.quantity,
                     cases_ordered  = cases_count,
                     case_cost      = bulk_item.price,
                     crv_per_unit   = bulk_item.crv_per_unit,
                     is_cost_taxed  = bulk_item.taxable,
                     is_crv_taxed   = bulk_item.crv_taxable, )
    item.save()
    messages.note("New item(s) added to order: %s." % (item,))

  item_list = []              # Items stored in the database
  new_items = []              # New entries not yet written to database

  # If any POST data was submitted, process it, since it might include
  # updates to existing items or new items.  We can distinguish the two
  # because existing items will include an "id." field.
  try:
      n = 0
      while True:
          n = str(int(n) + 1)

          try: number = int(request.POST['number.' + n])
          except ValueError: number = 0
          if number < 0: number = 0

          # Update to existing item in the database.  If quantity has
          # been cleared, then delete this item.  Otherwise, make any
          # appropriate edits.
          order_item = None
          try:
              id = int(request.POST['id.' + n])
              order_item = OrderItem.objects.get(id=id)
          except: pass

          if order_item:
              if not number:
                  order_item.delete()
              else:
                  order_item.number = number
                  order_item.quantity \
                      = int(request.POST['quantity.' + n])
                  order_item.cost_taxable \
                      = Decimal(request.POST['taxable.' + n])
                  order_item.cost_nontaxable \
                      = Decimal(request.POST['nontaxable.' + n])
                  order_item.save()
              continue

          # Filling in details for an entry.  If complete, save to the
          # database.
          if request.POST.has_key('type_code.' + n):
              if not number: continue

              try:
                  bulk_code = int(request.POST['type_code.' + n])
                  bulk_type = BulkItem.objects.get(bulkid=bulk_code)
                  quantity = int(request.POST['quantity.' + n])
                  nontaxable = Decimal(request.POST['nontaxable.' + n])
                  taxable = Decimal(request.POST['taxable.' + n])
                  order_item = OrderItem(order=order,
                                         bulk_type=bulk_type,
                                         quantity=quantity,
                                         number=number,
                                         cost_taxable=taxable,
                                         cost_nontaxable=nontaxable)
                  order_item.save()
              except:
                  pass

              continue

          # New entry.  Perform a search based on the name for matching
          # items, and add them to new_items so the user can fill in the rest
          # of the details.
          name = request.POST['type.' + n]
          if not name: continue

          if not number: number = ""
          matches = BulkItem.objects.filter(description__icontains=name)

          # If there were no matches, re-present the query to the user.
          if len(matches) == 0:
              new_items.append({'blank': True,
                                'type': name})

          # Force user to re-enter numbers if multiple matches occurred.
          if len(matches) > 1: number = ""

          for m in matches:
              new_items.append({'blank': False,
                                'type': m,
                                'number': number,
                                'quantity': m.quantity,
                                'nontaxable': m.cost_nontaxable(),
                                'taxable': m.cost_taxable()})
  except KeyError:
      # Assume we hit the end of the inputs
      pass

  # Include all items listed in the database for this order.
  total_taxed    = Decimal("0.00")
  total_nontaxed = Decimal("0.00")

  items = order.orderitem_set.order_by('id')
  for i in items: 
    if i.case_cost != i.bulk_type.price or i.crv_per_unit != i.bulk_type.crv_per_unit:
        i.message = "Price differs from bulk data"
    i.ammount = i.case_cost * i.cases_ordered
    i.crv_ammount = i.crv_per_unit * i.units_per_case * i.cases_ordered
    if i.is_cost_taxed:
      total_taxed += i.ammount
    else:
      total_nontaxed += i.ammount
    if i.is_crv_taxed:
      total_taxed += i.crv_ammount
    else:
      total_nontaxed += i.crv_ammount
    i.price_differs = i.case_cost != i.bulk_type.price
    i.crv_differes = i.crv_per_unit != i.bulk_type.crv_per_unit
    i.quantity_differs = i.units_per_case != i.bulk_type.quantity

  total = total_nontaxed + total_taxed * (1 + order.tax_rate)
  total = total.quantize(Decimal("0.01"))

  messages.extend({'user': request.user,
                   'title': 'Order Summary - ' + str(order.date),
                   'details_form': order_form,
                   'order': order,
                   'items': items,
                   'total_notax': total_nontaxed,
                   'total_tax': total_taxed,
                   'total': total,
                   'bulk_items' : BulkItem.objects.all().order_by('description')})

  return render_to_response('orders/order_summery.html', messages)
                               
@edit_orders_required
def new_order(request):
  order_form = OrderForm()
  messages = BobMessages()
  if 'save_details' in request.POST:
    order_form = OrderForm(request.POST)
    if order_form.is_valid():
      newOrder = Order(date = order_form.cleaned_data['date'],
                       description = order_form.cleaned_data['description'],
                       amount = order_form.cleaned_data['amount'],
                       tax_rate = order_form.cleaned_data['sales_tax_rate'])
      newOrder.save()
      newId = newOrder.id
      redirect(reverse('chezbob.orders.views.order_summary', args=(newId,)))
    else:
      for error_field in order_form.errors:
        messages.error("Field %s: %s" % (error_field, order_form[error_field].errors));
  messages.extend({'user': request.user,
                   'title': 'New Order',
                   'details_form': OrderForm(),
                   'order': {},
                   'items': [],
                   'total_notax': 0,
                   'total_tax': 0,
                   'total': 0,
                   'bulk_items' : BulkItem.objects.all().order_by('description')})
  return render_to_response('orders/order_summery.html', messages)
